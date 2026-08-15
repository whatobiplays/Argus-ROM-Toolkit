//! Application-owned LibraryScan traversal and reconciliation.
//!
//! The indexer owns recursion/traversal, the fixed Phase 001 discovery
//! policy, incremental positive-observation checkpoints, per-root terminal
//! assembly, and cancellation checkpoints. The source provider enumerates
//! one native scope at a time and never recurses on its own.

use crate::jobs::{ScanRunRepository, SourceEntryRepository};
use crate::sources::library::LibraryRootRepository;
use crate::sources::library::{map_persistence_error, now_millis};
use crate::sources::{
    DiscoveryPath, EnumerationOutcome, LibrarySourceAccess, ObservedEntryKind,
    RelativeSourceLocator, SourceAccessError, SourceEntryClassification, SourceEntryKind,
    SourceObservation,
};
use crate::unit_of_work::UnitOfWork;
use crate::{
    ApplicationError, ApplicationEvent, ApplicationPortError, ApplicationPortError::EventRecording,
    ApplicationPortError::Persistence, ErrorCode, JobProgress, JobProgressReporter, JobRunState,
    LibraryRootAvailability, LibraryRootChanged, LibraryRootLastScanStatus,
    LibraryRootLastScanSummary, NewSourceEntry, OperationCompletion, OperationContext, SafeContext,
    ScanRunStatus, SourceEntriesChangeScope, SourceEntriesChanged, SourceEntryId,
    UnitOfWorkFactory,
};

/// One pending positive observation with its committed parent identity.
struct PendingObservation {
    parent_source_entry_id: Option<SourceEntryId>,
    observation: SourceObservation,
}

/// One committed entry in a checkpoint batch.
struct CommittedEntry {
    source_entry_id: SourceEntryId,
    kind: SourceEntryKind,
    relative_locator: RelativeSourceLocator,
}

/// One scheduled enumeration scope.
enum Scope {
    Root,
    Child {
        parent_source_entry_id: SourceEntryId,
        relative_locator: RelativeSourceLocator,
    },
}

/// Application-owned library scan execution handler.
pub struct LibraryScanOperationHandler<A, U, S> {
    plan: crate::LibraryScanExecutionPlan,
    access: A,
    unit_of_work: U,
    event_sink: S,
    checkpoint_size: usize,
}

impl<A, U, S> LibraryScanOperationHandler<A, U, S>
where
    A: LibrarySourceAccess,
    U: UnitOfWorkFactory + Clone + Send + Sync,
    S: crate::jobs::ApplicationEventSink,
{
    /// Composes the frozen plan, execution-scoped provider access, Unit of
    /// Work factory, post-commit event sink, and bounded checkpoint size.
    pub fn new(
        plan: crate::LibraryScanExecutionPlan,
        access: A,
        unit_of_work: U,
        event_sink: S,
        checkpoint_size: usize,
    ) -> Self {
        Self {
            plan,
            access,
            unit_of_work,
            event_sink,
            checkpoint_size: checkpoint_size.max(1),
        }
    }

    fn execute_inner(
        &self,
        context: &OperationContext,
        is_cancelled: &dyn Fn() -> bool,
        progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError> {
        let root = match self.access.resolve_root() {
            Ok(root) => root,
            Err(error) => {
                return self.root_failure(context, error);
            }
        };
        if is_cancelled() {
            return self.finish_cancelled(context);
        }

        let mut committed_entries = 0_u64;
        let mut issues = 0_u64;
        let mut cancelled = false;
        let mut pending: Vec<PendingObservation> = Vec::new();
        let mut stack = vec![Scope::Root];

        while let Some(scope) = stack.pop() {
            if is_cancelled() {
                cancelled = true;
                break;
            }
            let enumeration = match &scope {
                Scope::Root => self
                    .access
                    .enumerate_root_direct_children(&root, is_cancelled),
                Scope::Child {
                    relative_locator, ..
                } => self
                    .access
                    .enumerate_direct_children(&root, relative_locator, is_cancelled),
            };
            let enumeration = match enumeration {
                Ok(result) => result,
                Err(error) => {
                    if error == SourceAccessError::Cancelled {
                        cancelled = true;
                        break;
                    }
                    if matches!(scope, Scope::Root) {
                        return self.root_failure(context, error);
                    }
                    issues += 1;
                    continue;
                }
            };
            match enumeration.outcome() {
                EnumerationOutcome::Cancelled => {
                    cancelled = true;
                    break;
                }
                EnumerationOutcome::Complete => {}
                EnumerationOutcome::Partial
                | EnumerationOutcome::Failed
                | EnumerationOutcome::Unavailable => {
                    issues += 1;
                }
            }

            for observation in enumeration.observations() {
                let parent_source_entry_id = match &scope {
                    Scope::Root => None,
                    Scope::Child {
                        parent_source_entry_id,
                        ..
                    } => Some(*parent_source_entry_id),
                };
                pending.push(PendingObservation {
                    parent_source_entry_id,
                    observation: observation.clone(),
                });
                if pending.len() >= self.checkpoint_size {
                    let committed = self.commit_checkpoint(
                        context,
                        progress,
                        &mut pending,
                        &mut committed_entries,
                    )?;
                    stack.extend(committed.into_iter().filter_map(|entry| {
                        (entry.kind == SourceEntryKind::Directory).then_some(Scope::Child {
                            parent_source_entry_id: entry.source_entry_id,
                            relative_locator: entry.relative_locator,
                        })
                    }));
                }
            }
            if !pending.is_empty() {
                let committed = self.commit_checkpoint(
                    context,
                    progress,
                    &mut pending,
                    &mut committed_entries,
                )?;
                stack.extend(committed.into_iter().filter_map(|entry| {
                    (entry.kind == SourceEntryKind::Directory).then_some(Scope::Child {
                        parent_source_entry_id: entry.source_entry_id,
                        relative_locator: entry.relative_locator,
                    })
                }));
            }
            if is_cancelled() {
                cancelled = true;
                break;
            }
        }

        if !pending.is_empty() {
            let committed =
                self.commit_checkpoint(context, progress, &mut pending, &mut committed_entries)?;
            stack.extend(committed.into_iter().filter_map(|entry| {
                (entry.kind == SourceEntryKind::Directory).then_some(Scope::Child {
                    parent_source_entry_id: entry.source_entry_id,
                    relative_locator: entry.relative_locator,
                })
            }));
        }

        if cancelled {
            return self.finish_cancelled(context);
        }
        if issues > 0 {
            return self.finish_partial(context);
        }
        self.finish_complete(context)
    }

    fn commit_checkpoint(
        &self,
        context: &OperationContext,
        progress: &dyn JobProgressReporter,
        pending: &mut Vec<PendingObservation>,
        committed_entries: &mut u64,
    ) -> Result<Vec<CommittedEntry>, ApplicationError> {
        let entries: Vec<NewSourceEntry> = pending
            .iter()
            .map(|pending_observation| map_observation(&self.plan, pending_observation))
            .collect();
        let ids = self
            .unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                let mut ids = Vec::with_capacity(entries.len());
                for entry in entries {
                    ids.push(scope.source_entries().upsert(entry)?);
                }
                scope.commit()?;
                Ok::<_, ApplicationPortError>(ids)
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;
        let committed: Vec<CommittedEntry> = pending
            .iter()
            .zip(ids)
            .map(|(pending_observation, source_entry_id)| CommittedEntry {
                source_entry_id,
                kind: source_entry_kind(pending_observation.observation.observed_kind()),
                relative_locator: pending_observation.observation.relative_locator().clone(),
            })
            .collect();
        *committed_entries += committed.len() as u64;
        pending.clear();
        self.event_sink
            .publish(ApplicationEvent::SourceEntriesChanged(
                SourceEntriesChanged {
                    library_root_id: self.plan.library_root_id(),
                    scope: SourceEntriesChangeScope::EntireRootHierarchy,
                },
            ));
        let progress_update = JobProgress::new(
            self.plan.job_run_id(),
            "discovering",
            Some(*committed_entries),
            None,
            Some("library_scan.discovering"),
            now_millis(),
        )
        .expect("committed units never exceed an unknown total");
        progress.report(progress_update)?;
        Ok(committed)
    }

    fn finish_cancelled(
        &self,
        context: &OperationContext,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Cancelled,
            LibraryRootLastScanStatus::Cancelled,
            None,
            None,
        )?;
        Ok(OperationCompletion::new(JobRunState::Cancelled, None, None))
    }

    fn finish_partial(
        &self,
        context: &OperationContext,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Partial,
            LibraryRootLastScanStatus::Partial,
            Some("incomplete_scope"),
            None,
        )?;
        Ok(OperationCompletion::new(
            JobRunState::CompletedWithIssues,
            None,
            None,
        ))
    }

    fn finish_complete(
        &self,
        context: &OperationContext,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Complete,
            LibraryRootLastScanStatus::Complete,
            None,
            None,
        )?;
        Ok(OperationCompletion::new(JobRunState::Completed, None, None))
    }

    fn root_failure(
        &self,
        context: &OperationContext,
        error: SourceAccessError,
    ) -> Result<OperationCompletion, ApplicationError> {
        match error {
            SourceAccessError::SourceUnavailable | SourceAccessError::AuthorizationUnavailable => {
                self.terminalize(
                    context,
                    ScanRunStatus::Failed,
                    LibraryRootLastScanStatus::Unavailable,
                    Some("source_unavailable"),
                    Some(LibraryRootAvailability::Unavailable),
                )?;
            }
            _ => {
                self.terminalize(
                    context,
                    ScanRunStatus::Failed,
                    LibraryRootLastScanStatus::Failed,
                    Some("source_access_failed"),
                    None,
                )?;
            }
        }
        Ok(OperationCompletion::new(JobRunState::Failed, None, None))
    }

    fn terminalize(
        &self,
        context: &OperationContext,
        status: ScanRunStatus,
        last_scan_status: LibraryRootLastScanStatus,
        failure_reason: Option<&str>,
        availability: Option<LibraryRootAvailability>,
    ) -> Result<(), ApplicationError> {
        let completed_at_ms = now_millis();
        let plan = self.plan.clone();
        let failure_reason = failure_reason.map(str::to_owned);
        self.unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                scope.scan_runs().set_status(
                    plan.scan_run_id(),
                    status,
                    Some(completed_at_ms),
                    failure_reason,
                )?;
                let summary = LibraryRootLastScanSummary::new(
                    plan.scan_run_id().to_string(),
                    plan.job_run_id().to_string(),
                    last_scan_status,
                    plan.started_at_ms(),
                    Some(completed_at_ms),
                );
                scope
                    .library_roots()
                    .set_last_scan(plan.library_root_id(), Some(summary))?;
                if let Some(availability) = availability {
                    scope
                        .library_roots()
                        .set_availability(plan.library_root_id(), availability)?;
                }
                scope.commit()
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;
        self.event_sink
            .publish(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                library_root_id: self.plan.library_root_id(),
            }));
        Ok(())
    }
}

impl<A, U, S> crate::BackgroundOperationHandler for LibraryScanOperationHandler<A, U, S>
where
    A: LibrarySourceAccess,
    U: UnitOfWorkFactory + Clone + Send + Sync,
    S: crate::jobs::ApplicationEventSink,
{
    fn execute(
        &self,
        context: &OperationContext,
        is_cancelled: &dyn Fn() -> bool,
        progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.execute_inner(context, is_cancelled, progress)
            .or_else(|error| {
                let code = Some(error.code.as_str().to_owned());
                self.terminalize(
                    context,
                    ScanRunStatus::Failed,
                    LibraryRootLastScanStatus::Failed,
                    Some("internal"),
                    None,
                )?;
                Ok(OperationCompletion::new(JobRunState::Failed, code, None))
            })
    }

    fn cancelled_before_execution(
        &self,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Cancelled,
            LibraryRootLastScanStatus::Cancelled,
            None,
            None,
        )
    }
}

fn map_observation(
    plan: &crate::LibraryScanExecutionPlan,
    pending: &PendingObservation,
) -> NewSourceEntry {
    let observation = &pending.observation;
    let display_location = display_location_of(observation.discovery_path());
    NewSourceEntry::new(
        plan.library_root_id(),
        pending.parent_source_entry_id,
        observation.relative_locator().clone(),
        observation.locator_key().clone(),
        observation.display_name(),
        display_location,
        source_entry_kind(observation.observed_kind()),
        source_entry_classification(observation.observed_kind()),
        observation.provider_native_identity().map(str::to_owned),
        observation.source_fingerprint().map(str::to_owned),
        plan.scan_run_id(),
    )
}

fn source_entry_kind(observed: ObservedEntryKind) -> SourceEntryKind {
    match observed {
        ObservedEntryKind::Directory => SourceEntryKind::Directory,
        ObservedEntryKind::File => SourceEntryKind::File,
        ObservedEntryKind::LinkLike => SourceEntryKind::LinkLike,
        ObservedEntryKind::Other => SourceEntryKind::Unknown,
    }
}

fn source_entry_classification(observed: ObservedEntryKind) -> SourceEntryClassification {
    match observed {
        ObservedEntryKind::Directory => SourceEntryClassification::Container,
        ObservedEntryKind::File => SourceEntryClassification::Unknown,
        ObservedEntryKind::LinkLike => SourceEntryClassification::Ignored,
        ObservedEntryKind::Other => SourceEntryClassification::Ignored,
    }
}

fn display_location_of(path: &DiscoveryPath) -> String {
    let segments: Vec<&str> = path
        .segments()
        .iter()
        .map(|segment| segment.as_str())
        .collect();
    if segments.is_empty() {
        String::new()
    } else {
        segments.join("/")
    }
}

fn map_port_error(trace_id: crate::TraceId, error: ApplicationPortError) -> ApplicationError {
    match error {
        Persistence(error) => map_persistence_error(trace_id, error),
        EventRecording => {
            ApplicationError::from_code(ErrorCode::InternalUnexpected, trace_id, SafeContext::new())
                .expect("internal unexpected uses an allowlisted empty context")
        }
    }
}
