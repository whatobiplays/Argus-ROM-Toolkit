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
    ApplicationPortError::Persistence, BackgroundOperationStopReason, ErrorCode, JobProgress,
    JobProgressReporter, JobRunState, LibraryRootAvailability, LibraryRootChanged,
    LibraryRootLastScanStatus, LibraryRootLastScanSummary, NativeIdentityMatch, NewSourceEntry,
    OperationCompletion, OperationContext, PersistenceError, SafeContext, ScanRunId, ScanRunStatus,
    SourceEntriesChangeScope, SourceEntriesChanged, SourceEntryId, UnitOfWorkFactory,
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

/// One exact scope whose enumeration completed and may later be finalized.
///
/// Finalization is deferred until discovery has seen all available
/// observations so a move from an earlier-traversed scope to a later one can
/// preserve identity before the old scope's absences are removed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct CompletedScope {
    parent_source_entry_id: Option<SourceEntryId>,
}

/// Aggregate outcome of the deferred finalization phase.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct FinalizationOutcome {
    stop_reason: Option<BackgroundOperationStopReason>,
    suppressed: bool,
}

/// One per-scope finalization transaction outcome.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum FinalizeWork {
    Finalized(u64),
    Suppressed,
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

    /// Terminalizes an admitted child as `Cancelled` without resolving or
    /// enumerating its provider. This is used by job-level cancellation when
    /// a not-yet-started child must still become durable before parent
    /// termination.
    pub fn cancel_without_execution(
        &self,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Cancelled,
            LibraryRootLastScanStatus::Cancelled,
            None,
            None,
            None,
        )
    }

    /// Terminalizes an admitted child as `Failed` without resolving or
    /// enumerating its provider, used when registration of an
    /// already-admitted execution fails so no orphan nonterminal ScanRun
    /// survives. This mirrors the single-root `fail_unregistered_scan`
    /// contract for every child of a multi-root Scan All job.
    pub fn fail_without_execution(
        &self,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Failed,
            LibraryRootLastScanStatus::Failed,
            Some("admission_registration_failed"),
            None,
            None,
        )
    }

    fn execute_inner(
        &self,
        context: &OperationContext,
        stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
        progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError> {
        let root = match self.access.resolve_root() {
            Ok(root) => root,
            Err(error) => {
                return self.root_failure(context, error);
            }
        };
        self.commit_availability_available(context)?;
        if let Some(reason) = stop_reason() {
            return self.finish_stopped(context, reason, 0, 0, 0);
        }

        let mut committed_entries = 0_u64;
        let mut observed_entries = 0_u64;
        let mut issues = 0_u64;
        let mut stopped = None;
        let mut root_unavailable = false;
        let mut root_incomplete = false;
        let mut completed_scopes: Vec<CompletedScope> = Vec::new();
        let mut pending: Vec<PendingObservation> = Vec::new();
        let mut stack = vec![Scope::Root];

        while let Some(scope) = stack.pop() {
            if let Some(reason) = stop_reason() {
                stopped = Some(reason);
                break;
            }
            let should_stop = || stop_reason().is_some();
            let enumeration = match &scope {
                Scope::Root => self
                    .access
                    .enumerate_root_direct_children(&root, &should_stop),
                Scope::Child {
                    relative_locator, ..
                } => self
                    .access
                    .enumerate_direct_children(&root, relative_locator, &should_stop),
            };
            let enumeration = match enumeration {
                Ok(result) => result,
                Err(error) => {
                    if let Some(reason) = stop_reason() {
                        stopped = Some(reason);
                        break;
                    }
                    if error == SourceAccessError::Cancelled {
                        stopped = Some(BackgroundOperationStopReason::CancellationRequested);
                        break;
                    }
                    if matches!(scope, Scope::Root) {
                        return self.root_failure(context, error);
                    }
                    issues += 1;
                    continue;
                }
            };
            let parent_source_entry_id = match &scope {
                Scope::Root => None,
                Scope::Child {
                    parent_source_entry_id,
                    ..
                } => Some(*parent_source_entry_id),
            };
            match enumeration.outcome() {
                EnumerationOutcome::Cancelled => {
                    stopped = Some(
                        stop_reason()
                            .unwrap_or(BackgroundOperationStopReason::CancellationRequested),
                    );
                    break;
                }
                EnumerationOutcome::Complete => {
                    completed_scopes.push(CompletedScope {
                        parent_source_entry_id,
                    });
                }
                EnumerationOutcome::Unavailable if matches!(scope, Scope::Root) => {
                    root_unavailable = true;
                }
                EnumerationOutcome::Partial | EnumerationOutcome::Failed => {
                    if matches!(scope, Scope::Root) {
                        root_incomplete = true;
                    }
                    issues += 1;
                }
                EnumerationOutcome::Unavailable => {
                    issues += 1;
                }
            }

            for observation in enumeration.observations() {
                observed_entries += 1;
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
                        observed_entries,
                        issues,
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
                    observed_entries,
                    issues,
                )?;
                stack.extend(committed.into_iter().filter_map(|entry| {
                    (entry.kind == SourceEntryKind::Directory).then_some(Scope::Child {
                        parent_source_entry_id: entry.source_entry_id,
                        relative_locator: entry.relative_locator,
                    })
                }));
            }
            if let Some(reason) = stop_reason() {
                stopped = Some(reason);
                break;
            }
        }

        if stopped.is_none() && !pending.is_empty() {
            let committed = self.commit_checkpoint(
                context,
                progress,
                &mut pending,
                &mut committed_entries,
                observed_entries,
                issues,
            )?;
            stack.extend(committed.into_iter().filter_map(|entry| {
                (entry.kind == SourceEntryKind::Directory).then_some(Scope::Child {
                    parent_source_entry_id: entry.source_entry_id,
                    relative_locator: entry.relative_locator,
                })
            }));
        }

        if let Some(reason) = stopped.or_else(stop_reason) {
            return self.finish_stopped(
                context,
                reason,
                observed_entries,
                committed_entries,
                issues,
            );
        }
        if root_unavailable {
            return self.finish_root_unavailable(
                context,
                observed_entries,
                committed_entries,
                issues,
            );
        }

        let finalization =
            self.finalize_completed_scopes(context, &completed_scopes, stop_reason)?;
        if let Some(reason) = finalization.stop_reason {
            return self.finish_stopped(
                context,
                reason,
                observed_entries,
                committed_entries,
                issues,
            );
        }
        if root_incomplete && committed_entries == 0 {
            return self.finish_failed(context, observed_entries, committed_entries, issues);
        }
        if finalization.suppressed {
            return self.finish_partial(
                context,
                "finalization_authority_changed",
                observed_entries,
                committed_entries,
                issues,
            );
        }
        if issues > 0 {
            return self.finish_partial(
                context,
                "incomplete_scope",
                observed_entries,
                committed_entries,
                issues,
            );
        }
        self.finish_complete(context, observed_entries, committed_entries, issues)
    }

    fn commit_checkpoint(
        &self,
        context: &OperationContext,
        progress: &dyn JobProgressReporter,
        pending: &mut Vec<PendingObservation>,
        committed_entries: &mut u64,
        observed_entries: u64,
        issues: u64,
    ) -> Result<Vec<CommittedEntry>, ApplicationError> {
        let entries: Vec<NewSourceEntry> = pending
            .iter()
            .map(|pending_observation| map_observation(&self.plan, pending_observation))
            .collect();
        let scan_run_id = self.plan.scan_run_id();
        let committed_before = *committed_entries;
        let ids = self
            .unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                let mut ids = Vec::with_capacity(entries.len());
                for entry in entries {
                    let mut source_entries = scope.source_entries();
                    ids.push(reconcile_positive(&mut source_entries, entry, scan_run_id)?);
                }
                let committed_total = committed_before + ids.len() as u64;
                scope.scan_runs().set_progress_facts(
                    scan_run_id,
                    observed_entries,
                    committed_total,
                    issues,
                )?;
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

    /// Commits the current availability evidence after a successful root
    /// resolution. Successful root access is the only path that marks the
    /// root `Available`; nested failures and cancellation never do.
    fn commit_availability_available(
        &self,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let root_id = self.plan.library_root_id();
        self.unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                scope
                    .library_roots()
                    .set_availability(root_id, LibraryRootAvailability::Available)?;
                scope.commit()
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;
        self.event_sink
            .publish(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                library_root_id: root_id,
            }));
        Ok(())
    }

    /// Runs the deferred exact-scope finalization phase after discovery has
    /// consumed all available observations. Each scope is finalized in one
    /// coherent transaction that first rechecks current plan authority.
    fn finalize_completed_scopes(
        &self,
        context: &OperationContext,
        completed_scopes: &[CompletedScope],
        stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
    ) -> Result<FinalizationOutcome, ApplicationError> {
        let mut outcome = FinalizationOutcome::default();
        for scope in completed_scopes {
            if let Some(reason) = stop_reason() {
                outcome.stop_reason = Some(reason);
                break;
            }
            let plan = self.plan.clone();
            let root_id = plan.library_root_id();
            let parent_source_entry_id = scope.parent_source_entry_id;
            let scan_run_id = plan.scan_run_id();
            let work = self
                .unit_of_work
                .clone()
                .execute(context, move |mut scope| {
                    let Some(current) = scope.library_roots().get_scan_authority(root_id)? else {
                        scope.commit()?;
                        return Ok::<_, ApplicationPortError>(FinalizeWork::Suppressed);
                    };
                    if current.source_config_revision() != plan.source_config_revision()
                        || current.config_revision() != plan.root_config_revision()
                        || current.discovery_policy_revision() != plan.discovery_policy_revision()
                    {
                        scope.commit()?;
                        return Ok::<_, ApplicationPortError>(FinalizeWork::Suppressed);
                    }
                    let deleted = scope.source_entries().finalize_absent_scope(
                        root_id,
                        parent_source_entry_id,
                        scan_run_id,
                    )?;
                    scope.commit()?;
                    Ok::<_, ApplicationPortError>(FinalizeWork::Finalized(deleted))
                })
                .map_err(|error| map_port_error(context.trace_id(), error))?;
            match work {
                FinalizeWork::Suppressed => outcome.suppressed = true,
                FinalizeWork::Finalized(deleted) if deleted > 0 => {
                    self.event_sink
                        .publish(ApplicationEvent::SourceEntriesChanged(
                            SourceEntriesChanged {
                                library_root_id: self.plan.library_root_id(),
                                scope: SourceEntriesChangeScope::EntireRootHierarchy,
                            },
                        ));
                }
                FinalizeWork::Finalized(_) => {}
            }
        }
        Ok(outcome)
    }

    fn finish_cancelled(
        &self,
        context: &OperationContext,
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Cancelled,
            LibraryRootLastScanStatus::Cancelled,
            None,
            None,
            Some((observed_entries, entries_committed, issues)),
        )?;
        Ok(OperationCompletion::new(JobRunState::Cancelled, None, None))
    }

    fn finish_stopped(
        &self,
        context: &OperationContext,
        reason: BackgroundOperationStopReason,
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        if reason == BackgroundOperationStopReason::CancellationRequested {
            return self.finish_cancelled(context, observed_entries, entries_committed, issues);
        }
        let failure_reason = match reason {
            BackgroundOperationStopReason::ExecutionHostTimeout => "execution_host_timeout",
            BackgroundOperationStopReason::ExecutionHostLost => "execution_host_lost",
            BackgroundOperationStopReason::CancellationRequested => unreachable!(),
        };
        if entries_committed > 0 {
            self.finish_partial(
                context,
                failure_reason,
                observed_entries,
                entries_committed,
                issues,
            )
        } else {
            self.finish_failed_with_reason(
                context,
                failure_reason,
                observed_entries,
                entries_committed,
                issues,
            )
        }
    }

    fn finish_partial(
        &self,
        context: &OperationContext,
        failure_reason: &str,
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Partial,
            LibraryRootLastScanStatus::Partial,
            Some(failure_reason),
            None,
            Some((observed_entries, entries_committed, issues)),
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
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Complete,
            LibraryRootLastScanStatus::Complete,
            None,
            None,
            Some((observed_entries, entries_committed, issues)),
        )?;
        Ok(OperationCompletion::new(JobRunState::Completed, None, None))
    }

    /// Terminalizes a root scan that produced no meaningful indexing result.
    fn finish_failed(
        &self,
        context: &OperationContext,
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.finish_failed_with_reason(
            context,
            "source_access_failed",
            observed_entries,
            entries_committed,
            issues,
        )
    }

    fn finish_failed_with_reason(
        &self,
        context: &OperationContext,
        failure_reason: &str,
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Failed,
            LibraryRootLastScanStatus::Failed,
            Some(failure_reason),
            None,
            Some((observed_entries, entries_committed, issues)),
        )?;
        Ok(OperationCompletion::new(JobRunState::Failed, None, None))
    }

    /// Terminalizes a root-level unavailable scan: `Failed` scan, `Unavailable`
    /// last-scan summary, and `Unavailable` availability evidence.
    fn finish_root_unavailable(
        &self,
        context: &OperationContext,
        observed_entries: u64,
        entries_committed: u64,
        issues: u64,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.terminalize(
            context,
            ScanRunStatus::Failed,
            LibraryRootLastScanStatus::Unavailable,
            Some("source_unavailable"),
            Some(LibraryRootAvailability::Unavailable),
            Some((observed_entries, entries_committed, issues)),
        )?;
        Ok(OperationCompletion::new(JobRunState::Failed, None, None))
    }

    fn root_failure(
        &self,
        context: &OperationContext,
        error: SourceAccessError,
    ) -> Result<OperationCompletion, ApplicationError> {
        match error {
            SourceAccessError::SourceUnavailable | SourceAccessError::AuthorizationUnavailable => {
                self.finish_root_unavailable(context, 0, 0, 0)
            }
            _ => self.finish_failed(context, 0, 0, 0),
        }
    }

    fn terminalize(
        &self,
        context: &OperationContext,
        status: ScanRunStatus,
        last_scan_status: LibraryRootLastScanStatus,
        failure_reason: Option<&str>,
        availability: Option<LibraryRootAvailability>,
        progress_facts: Option<(u64, u64, u64)>,
    ) -> Result<(), ApplicationError> {
        let completed_at_ms = now_millis();
        let plan = self.plan.clone();
        let failure_reason = failure_reason.map(str::to_owned);
        self.unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                if let Some((observed, committed, issues)) = progress_facts {
                    scope.scan_runs().set_progress_facts(
                        plan.scan_run_id(),
                        observed,
                        committed,
                        issues,
                    )?;
                }
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
        stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
        progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError> {
        self.execute_inner(context, stop_reason, progress)
            .or_else(|error| {
                let code = Some(error.code.as_str().to_owned());
                self.terminalize(
                    context,
                    ScanRunStatus::Failed,
                    LibraryRootLastScanStatus::Failed,
                    Some("internal"),
                    None,
                    None,
                )?;
                Ok(OperationCompletion::new(JobRunState::Failed, code, None))
            })
    }

    fn stopped_before_execution(
        &self,
        context: &OperationContext,
        reason: BackgroundOperationStopReason,
    ) -> Result<(), ApplicationError> {
        self.finish_stopped(context, reason, 0, 0, 0).map(|_| ())
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

/// Reconciles one positive observation against persisted state.
///
/// Exact locator observations update the existing entry in place. Otherwise a
/// provider-native identity preserves `SourceEntryId` only when exactly one
/// total persisted candidate exists and that sole candidate was not already
/// positively observed by the current scan. Zero, multiple, or already-
/// observed candidates never guess continuity and create a new entry.
fn reconcile_positive(
    entries: &mut impl SourceEntryRepository,
    entry: NewSourceEntry,
    scan_run_id: ScanRunId,
) -> Result<SourceEntryId, PersistenceError> {
    let root_id = entry.library_root_id();
    if entries
        .find_by_locator_key(root_id, entry.locator_key())?
        .is_some()
    {
        return entries.upsert(entry);
    }
    if let Some(identity) = entry.provider_native_identity() {
        match entries.find_native_identity(root_id, identity)? {
            NativeIdentityMatch::Unique(candidate)
                if candidate.last_observed_scan_id() != scan_run_id =>
            {
                return entries.reconcile_move(entry, candidate.source_entry_id());
            }
            NativeIdentityMatch::None
            | NativeIdentityMatch::Ambiguous
            | NativeIdentityMatch::Unique(_) => {}
        }
    }
    entries.upsert(entry)
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
