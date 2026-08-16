//! Focused library-root configuration capabilities for Slice 001.

use std::sync::Arc;

use crate::jobs::{
    AdmittedLibraryScanJob, AdmittedScan, JobRunRepository, LibraryScanAdmissionContextRepository,
    LibraryScanAdmissionExclusion, LibraryScanAllAdmissionResult, LibraryScanAllRequestIdentity,
    LibraryScanAllRequestLookup, LibraryScanExecutionPlan, LibraryScanInvocationKind,
    LibraryScanTargetExclusionReason, LibraryScanTargetKind, LibraryScanTargetRepository,
    OPERATION_TYPE_LIBRARY_SCAN, OperationHandle, ScanRunRepository, SourceEntryRepository,
    StartLibraryScanAllResult,
};
use crate::{
    ApplicationError, ApplicationEvent, ApplicationPortError, ErrorCode, EventRecorder,
    FailureRole, JobRunId, JobRunState, LibraryRootChanged, LibraryRootId, LibraryRootsChanged,
    LibraryScanAdmissionResult, NewJobRun, NewLibraryScanAdmissionContext, NewLibraryScanTarget,
    NewScanRun, OperationContext, PersistenceError, SafeContext, SafeContextField,
    SafeContextValue, ScanRunId, StartLibraryScanResult, TechnicalClass, UnitOfWork,
    UnitOfWorkFactory,
};

use super::hierarchy::{
    GetSourceEntryHandler, GetSourceEntryQuery, ListSourceEntryChildrenHandler,
    ListSourceEntryChildrenQuery, SourceEntryChildrenPage, SourceEntryDetailProjection,
    SourceEntryQueries,
};
use super::provider::{
    LocalFilesystemBrowseCursor, LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage,
    LocalFilesystemBrowseProvider, LocalFilesystemBrowseRoot, LocalFilesystemProvider,
    LocalFilesystemRootSelection, MountedLocalFilesystemVolume, ProviderError, RootLocator,
    RootRelationship, SourceAccessError,
};

/// Application-owned current reachability evidence for one root.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryRootAvailability {
    /// Recent authoritative evidence shows the root is reachable/enumerable.
    Available,
    /// Recent authoritative evidence shows the root is unreachable.
    Unavailable,
    /// No sufficiently recent authoritative evidence exists.
    Unknown,
}

impl LibraryRootAvailability {
    /// Returns the canonical serialized availability value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Available => "available",
            Self::Unavailable => "unavailable",
            Self::Unknown => "unknown",
        }
    }
}

/// Closed historical root last-scan status vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryRootLastScanStatus {
    Complete,
    Partial,
    Unavailable,
    Cancelled,
    Failed,
    Abandoned,
}

impl LibraryRootLastScanStatus {
    /// Returns the canonical serialized status value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Complete => "complete",
            Self::Partial => "partial",
            Self::Unavailable => "unavailable",
            Self::Cancelled => "cancelled",
            Self::Failed => "failed",
            Self::Abandoned => "abandoned",
        }
    }
}

/// Bounded terminal scan-history summary carried by a root projection.
///
/// Identity values are opaque serialized projections; this type exists for
/// projection stability and is always absent (`NeverScanned`) in Slice 001.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootLastScanSummary {
    scan_run_id: String,
    job_run_id: String,
    status: LibraryRootLastScanStatus,
    started_at_ms: i64,
    completed_at_ms: Option<i64>,
}

impl LibraryRootLastScanSummary {
    /// Creates one bounded terminal scan summary.
    pub fn new(
        scan_run_id: String,
        job_run_id: String,
        status: LibraryRootLastScanStatus,
        started_at_ms: i64,
        completed_at_ms: Option<i64>,
    ) -> Self {
        Self {
            scan_run_id,
            job_run_id,
            status,
            started_at_ms,
            completed_at_ms,
        }
    }

    /// Returns the opaque scan-run identity projection.
    pub fn scan_run_id(&self) -> &str {
        &self.scan_run_id
    }

    /// Returns the opaque job-run identity projection.
    pub fn job_run_id(&self) -> &str {
        &self.job_run_id
    }

    /// Returns the terminal scan status.
    pub fn status(&self) -> LibraryRootLastScanStatus {
        self.status
    }

    /// Returns the scan start timestamp in milliseconds.
    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }

    /// Returns the scan completion timestamp in milliseconds, if terminal.
    pub fn completed_at_ms(&self) -> Option<i64> {
        self.completed_at_ms
    }
}

/// Bounded active scan-ownership summary carried by a root projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootActiveScanSummary {
    scan_run_id: String,
    job_run_id: String,
    owning_job_root_count: u32,
}

impl LibraryRootActiveScanSummary {
    /// Creates one bounded active ownership summary.
    pub fn new(scan_run_id: String, job_run_id: String, owning_job_root_count: u32) -> Self {
        Self {
            scan_run_id,
            job_run_id,
            owning_job_root_count,
        }
    }

    /// Returns the opaque scan-run identity projection.
    pub fn scan_run_id(&self) -> &str {
        &self.scan_run_id
    }

    /// Returns the opaque job-run identity projection.
    pub fn job_run_id(&self) -> &str {
        &self.job_run_id
    }

    /// Returns the number of roots owned by the owning job.
    pub fn owning_job_root_count(&self) -> u32 {
        self.owning_job_root_count
    }
}

/// Authoritative immutable projection of one configured library root.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootProjection {
    root_id: LibraryRootId,
    display_name: String,
    safe_location_presentation: String,
    availability: LibraryRootAvailability,
    last_scan: Option<LibraryRootLastScanSummary>,
    active_scan: Option<LibraryRootActiveScanSummary>,
}

impl LibraryRootProjection {
    /// Creates a projection with independent availability/scan dimensions.
    pub fn new(
        root_id: LibraryRootId,
        display_name: String,
        safe_location_presentation: String,
        availability: LibraryRootAvailability,
        last_scan: Option<LibraryRootLastScanSummary>,
        active_scan: Option<LibraryRootActiveScanSummary>,
    ) -> Self {
        Self {
            root_id,
            display_name,
            safe_location_presentation,
            availability,
            last_scan,
            active_scan,
        }
    }

    /// Returns the stable root identity.
    pub fn root_id(&self) -> LibraryRootId {
        self.root_id
    }

    /// Returns the application-owned display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the backend-produced safe location presentation.
    pub fn safe_location_presentation(&self) -> &str {
        &self.safe_location_presentation
    }

    /// Returns the independent availability dimension.
    pub fn availability(&self) -> LibraryRootAvailability {
        self.availability
    }

    /// Returns the terminal last-scan summary; absence means `NeverScanned`.
    pub fn last_scan(&self) -> Option<&LibraryRootLastScanSummary> {
        self.last_scan.as_ref()
    }

    /// Returns the current active-scan ownership summary, if any.
    pub fn active_scan(&self) -> Option<&LibraryRootActiveScanSummary> {
        self.active_scan.as_ref()
    }

    /// Returns a copy with the supplied terminal scan summary.
    pub fn with_last_scan(mut self, summary: LibraryRootLastScanSummary) -> Self {
        self.last_scan = Some(summary);
        self
    }

    /// Returns a copy with the supplied active-scan summary.
    pub fn with_active_scan(mut self, summary: LibraryRootActiveScanSummary) -> Self {
        self.active_scan = Some(summary);
        self
    }
}

/// Bounded authoritative root-list page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootPage {
    items: Vec<LibraryRootProjection>,
    offset: u32,
    page_size: u32,
    total_count: u32,
}

impl LibraryRootPage {
    /// Creates one bounded root page with authoritative ordering.
    pub fn new(
        items: Vec<LibraryRootProjection>,
        offset: u32,
        page_size: u32,
        total_count: u32,
    ) -> Self {
        Self {
            items,
            offset,
            page_size,
            total_count,
        }
    }

    /// Returns the page items in authoritative order.
    pub fn items(&self) -> &[LibraryRootProjection] {
        &self.items
    }

    /// Returns the requested offset.
    pub fn offset(&self) -> u32 {
        self.offset
    }

    /// Returns the requested page size.
    pub fn page_size(&self) -> u32 {
        self.page_size
    }

    /// Returns the total configured-root count.
    pub fn total_count(&self) -> u32 {
        self.total_count
    }
}

/// One existing root configuration exposed for provider relationship checks.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootConfiguration {
    root_id: LibraryRootId,
    locator: RootLocator,
    availability: LibraryRootAvailability,
}

/// One bounded synchronization request carrying current native mounts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SyncLocalFilesystemMountedVolumesCommand {
    volumes: Vec<MountedLocalFilesystemVolume>,
}

impl SyncLocalFilesystemMountedVolumesCommand {
    /// Creates one synchronization request from the native snapshot.
    pub fn new(volumes: Vec<MountedLocalFilesystemVolume>) -> Self {
        Self { volumes }
    }

    /// Returns the native facts without interpreting them in application code.
    pub fn volumes(&self) -> &[MountedLocalFilesystemVolume] {
        &self.volumes
    }
}

impl LibraryRootConfiguration {
    /// Creates one opaque configuration record without current availability
    /// evidence. Callers reading durable rows should use
    /// [`Self::with_availability`].
    pub fn new(root_id: LibraryRootId, locator: RootLocator) -> Self {
        Self {
            root_id,
            locator,
            availability: LibraryRootAvailability::Unknown,
        }
    }

    /// Creates one configuration record with its current persisted
    /// availability evidence.
    pub fn with_availability(
        root_id: LibraryRootId,
        locator: RootLocator,
        availability: LibraryRootAvailability,
    ) -> Self {
        Self {
            root_id,
            locator,
            availability,
        }
    }

    /// Returns the configured root identity.
    pub fn root_id(&self) -> LibraryRootId {
        self.root_id
    }

    /// Returns the opaque provider-owned locator.
    pub fn locator(&self) -> &RootLocator {
        &self.locator
    }

    /// Returns the current persisted availability evidence.
    pub fn availability(&self) -> LibraryRootAvailability {
        self.availability
    }
}

/// Complete durable root configuration for one insert.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewLibraryRoot {
    library_source_id: crate::LibrarySourceId,
    locator: RootLocator,
    display_name: String,
    safe_location_presentation: String,
    availability: LibraryRootAvailability,
    config_revision: u32,
}

/// Frozen root configuration facts required to build one scan plan.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootScanConfiguration {
    root_id: LibraryRootId,
    locator: RootLocator,
    display_name: String,
    safe_location_presentation: String,
    config_revision: u32,
    source_config_revision: u32,
    discovery_policy_revision: u32,
}

impl LibraryRootScanConfiguration {
    /// Creates one scan configuration view.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        root_id: LibraryRootId,
        locator: RootLocator,
        display_name: impl Into<String>,
        safe_location_presentation: impl Into<String>,
        config_revision: u32,
        source_config_revision: u32,
        discovery_policy_revision: u32,
    ) -> Self {
        Self {
            root_id,
            locator,
            display_name: display_name.into(),
            safe_location_presentation: safe_location_presentation.into(),
            config_revision,
            source_config_revision,
            discovery_policy_revision,
        }
    }

    /// Returns the configured root identity.
    pub fn root_id(&self) -> LibraryRootId {
        self.root_id
    }

    /// Returns the opaque provider-owned locator.
    pub fn locator(&self) -> &RootLocator {
        &self.locator
    }

    /// Returns the application-owned display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the safe location presentation.
    pub fn safe_location_presentation(&self) -> &str {
        &self.safe_location_presentation
    }

    /// Returns the root configuration revision.
    pub fn config_revision(&self) -> u32 {
        self.config_revision
    }

    /// Returns the owning source configuration revision.
    pub fn source_config_revision(&self) -> u32 {
        self.source_config_revision
    }

    /// Returns the current discovery-policy revision.
    pub fn discovery_policy_revision(&self) -> u32 {
        self.discovery_policy_revision
    }
}

impl NewLibraryRoot {
    /// Creates one root configuration for insertion.
    pub fn new(
        library_source_id: crate::LibrarySourceId,
        locator: RootLocator,
        display_name: String,
        safe_location_presentation: String,
        availability: LibraryRootAvailability,
        config_revision: u32,
    ) -> Self {
        Self {
            library_source_id,
            locator,
            display_name,
            safe_location_presentation,
            availability,
            config_revision,
        }
    }

    /// Returns the owning internal source identity.
    pub fn library_source_id(&self) -> crate::LibrarySourceId {
        self.library_source_id
    }

    /// Returns the opaque provider-owned locator.
    pub fn locator(&self) -> &RootLocator {
        &self.locator
    }

    /// Returns the application-owned display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the safe location presentation.
    pub fn safe_location_presentation(&self) -> &str {
        &self.safe_location_presentation
    }

    /// Returns the initial availability evidence.
    pub fn availability(&self) -> LibraryRootAvailability {
        self.availability
    }

    /// Returns the initial configuration revision.
    pub fn config_revision(&self) -> u32 {
        self.config_revision
    }
}

/// Independent authoritative root reads.
pub trait LibraryRootQueries {
    /// Lists a bounded authoritative root page.
    fn list(
        &self,
        context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<LibraryRootPage, PersistenceError>;

    /// Reads one current root projection, or `None` when not configured.
    fn get(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootProjection>, PersistenceError>;

    /// Lists existing opaque root configurations for provider comparison.
    fn list_root_configurations(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<LibraryRootConfiguration>, PersistenceError>;

    /// Reads the frozen root configuration facts for one scan plan.
    fn get_scan_configuration(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError>;
}

impl<Q> LibraryRootQueries for &Q
where
    Q: LibraryRootQueries,
{
    fn list(
        &self,
        context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<LibraryRootPage, PersistenceError> {
        (*self).list(context, offset, page_size)
    }

    fn get(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootProjection>, PersistenceError> {
        (*self).get(context, root_id)
    }

    fn list_root_configurations(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<LibraryRootConfiguration>, PersistenceError> {
        (*self).list_root_configurations(context)
    }

    fn get_scan_configuration(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        (*self).get_scan_configuration(context, root_id)
    }
}

/// Transaction-scoped internal library-source repository.
pub trait LibrarySourceRepository {
    /// Returns the single internal LocalFilesystem source, creating it on
    /// first use. Later calls reuse the durable identity.
    fn ensure_local_filesystem_source(
        &mut self,
    ) -> Result<crate::LibrarySourceId, PersistenceError>;
}

/// Transaction-scoped configured-root repository.
pub trait LibraryRootRepository {
    /// Inserts one root and returns its stable identity.
    fn insert(&mut self, root: NewLibraryRoot) -> Result<LibraryRootId, PersistenceError>;

    /// Deletes one current root and reports whether a row was removed.
    fn delete(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError>;

    /// Reports whether one current root is configured.
    fn exists(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError>;

    /// Updates application-owned root availability evidence.
    fn set_availability(
        &mut self,
        root_id: LibraryRootId,
        availability: LibraryRootAvailability,
    ) -> Result<bool, PersistenceError>;

    /// Updates the authoritative root last-scan summary; `None` clears it.
    fn set_last_scan(
        &mut self,
        root_id: LibraryRootId,
        summary: Option<LibraryRootLastScanSummary>,
    ) -> Result<bool, PersistenceError>;

    /// Reads current root/source/policy authority facts inside the active
    /// transaction, or `None` when the root is no longer configured. This is
    /// the destructive-finalization authority seam: finalization compares
    /// these revisions to the frozen scan plan immediately before mutation.
    fn get_scan_authority(
        &mut self,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError>;
}

/// Parameterized bounded root-list request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ListLibraryRootsQuery {
    offset: u32,
    page_size: u32,
}

impl ListLibraryRootsQuery {
    /// Creates a bounded list request.
    pub const fn new(offset: u32, page_size: u32) -> Self {
        Self { offset, page_size }
    }

    /// Returns the requested offset.
    pub const fn offset(self) -> u32 {
        self.offset
    }

    /// Returns the requested page size.
    pub const fn page_size(self) -> u32 {
        self.page_size
    }
}

/// One authoritative root-detail request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct GetLibraryRootQuery {
    root_id: LibraryRootId,
}

impl GetLibraryRootQuery {
    /// Creates a root-detail request for one stable identity.
    pub const fn new(root_id: LibraryRootId) -> Self {
        Self { root_id }
    }

    /// Returns the requested root identity.
    pub const fn root_id(self) -> LibraryRootId {
        self.root_id
    }
}

/// One root-only add request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AddLocalLibraryRootCommand {
    selection: LocalFilesystemRootSelection,
}

impl AddLocalLibraryRootCommand {
    /// Creates a root-only add command from the typed picker selection.
    pub fn new(selection: LocalFilesystemRootSelection) -> Self {
        Self { selection }
    }

    /// Returns the typed selection input.
    pub fn selection(&self) -> &LocalFilesystemRootSelection {
        &self.selection
    }
}

/// One root-removal request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RemoveLibraryRootCommand {
    root_id: LibraryRootId,
}

impl RemoveLibraryRootCommand {
    /// Creates a removal request for one stable root identity.
    pub const fn new(root_id: LibraryRootId) -> Self {
        Self { root_id }
    }

    /// Returns the root identity to remove.
    pub const fn root_id(self) -> LibraryRootId {
        self.root_id
    }
}

/// One single-root scan admission request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StartLibraryScanCommand {
    root_id: LibraryRootId,
}

impl StartLibraryScanCommand {
    /// Creates a scan request for one configured root.
    pub const fn new(root_id: LibraryRootId) -> Self {
        Self { root_id }
    }

    /// Returns the requested root identity.
    pub const fn root_id(self) -> LibraryRootId {
        self.root_id
    }
}

/// One multi-root Scan All admission request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StartLibraryScanAllCommand {
    request_identity: LibraryScanAllRequestIdentity,
}

impl StartLibraryScanAllCommand {
    /// Creates a Scan All request carrying the durable client request identity.
    pub fn new(request_identity: LibraryScanAllRequestIdentity) -> Self {
        Self { request_identity }
    }

    /// Returns the durable request identity used for ambiguity reconciliation.
    pub fn request_identity(&self) -> &LibraryScanAllRequestIdentity {
        &self.request_identity
    }
}

/// Typed outcome of one root-only add operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AddLocalLibraryRootResult {
    /// The root was durably configured.
    Added(LibraryRootProjection),
    /// The exact same validated selection is already configured.
    AlreadyConfigured(LibraryRootId),
    /// The selection provably overlaps one existing configured root.
    OverlapsExisting(LibraryRootId, RootRelationship),
}

/// Typed child LibraryScan admission issue for an Add & Scan workflow.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LibraryScanChildAdmissionIssue {
    /// The root already has an active scan owner.
    AlreadyScanning {
        library_root_id: LibraryRootId,
        active_job_run_id: JobRunId,
        active_scan_run_id: ScanRunId,
    },
    /// Child admission failed with one canonical bounded application error.
    AdmissionFailure(ApplicationError),
}

/// Typed outcome of one Add & Scan composite workflow.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AddLocalLibraryRootAndScanResult {
    /// The root committed and one child LibraryScan was admitted.
    AddedAndScanAdmitted(LibraryRootProjection, OperationHandle),
    /// The root committed but the child LibraryScan was not admitted.
    AddedButScanNotAdmitted(LibraryRootProjection, LibraryScanChildAdmissionIssue),
    /// The exact same validated selection is already configured.
    AlreadyConfigured(LibraryRootId),
    /// The selection provably overlaps one existing configured root.
    OverlapsExisting(LibraryRootId, RootRelationship),
}

/// One Add & Scan composite request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AddLocalLibraryRootAndScanCommand {
    selection: LocalFilesystemRootSelection,
}

impl AddLocalLibraryRootAndScanCommand {
    /// Creates one composite request from the typed picker selection.
    pub fn new(selection: LocalFilesystemRootSelection) -> Self {
        Self { selection }
    }

    /// Returns the typed selection input.
    pub fn selection(&self) -> &LocalFilesystemRootSelection {
        &self.selection
    }
}

/// Narrow runtime-supplied child LibraryScan admission capability.
///
/// SPEC-BE-013/SPEC-BE-009 permit the application Add & Scan workflow to
/// consume a runtime-supplied capability that durably admits the child scan
/// and establishes background-operation responsibility. Runtime registration
/// and scheduling remain owned by `ArgusRuntime`/`BackgroundOperationManager`;
/// the application workflow never sequences an independent add followed by a
/// separate scan call.
pub trait LibraryScanChildAdmission {
    /// Admits one durable child LibraryScan for a freshly committed root.
    fn admit(
        &self,
        library_root_id: LibraryRootId,
        context: &OperationContext,
        is_cancelled: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<crate::LibraryScanAdmissionResult, ApplicationError>;
}

/// Typed outcome of one root-removal operation for the active slice.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RemoveLibraryRootResult {
    /// The current Argus root configuration was removed.
    Removed,
    /// The root is owned by an active scan and was not removed.
    RootHasActiveScan {
        library_root_id: LibraryRootId,
        job_run_id: JobRunId,
        scan_run_id: ScanRunId,
        owning_job_root_count: u32,
    },
}

/// Handles the bounded authoritative root-list query.
pub struct ListLibraryRootsHandler<Q> {
    queries: Q,
}

impl<Q> ListLibraryRootsHandler<Q> {
    /// Composes the focused query capability.
    pub const fn new(queries: Q) -> Self {
        Self { queries }
    }
}

impl<Q> ListLibraryRootsHandler<Q>
where
    Q: LibraryRootQueries,
{
    /// Executes the bounded root-list query.
    pub fn handle(
        &self,
        query: ListLibraryRootsQuery,
        context: OperationContext,
    ) -> Result<LibraryRootPage, ApplicationError> {
        self.queries
            .list(&context, query.offset(), query.page_size())
            .map_err(|error| map_persistence_error(context.trace_id(), error))
    }
}

/// Handles the authoritative root-detail query.
pub struct GetLibraryRootHandler<Q> {
    queries: Q,
}

impl<Q> GetLibraryRootHandler<Q> {
    /// Composes the focused query capability.
    pub const fn new(queries: Q) -> Self {
        Self { queries }
    }
}

impl<Q> GetLibraryRootHandler<Q>
where
    Q: LibraryRootQueries,
{
    /// Executes the root-detail query. A syntactically valid but unconfigured
    /// root is a typed configuration failure, never a nullable projection.
    pub fn handle(
        &self,
        query: GetLibraryRootQuery,
        context: OperationContext,
    ) -> Result<LibraryRootProjection, ApplicationError> {
        self.queries
            .get(&context, query.root_id())
            .map_err(|error| map_persistence_error(context.trace_id(), error))?
            .ok_or_else(|| {
                application_error(
                    context.trace_id(),
                    ErrorCode::ConfigurationLibraryRootNotFound,
                )
            })
    }
}

/// Handles one transactional root-only add.
pub struct AddLocalLibraryRootHandler<P, Q, U> {
    provider: P,
    queries: Q,
    unit_of_work: U,
}

impl<P, Q, U> AddLocalLibraryRootHandler<P, Q, U> {
    /// Composes the provider, query, and Unit of Work capabilities.
    pub const fn new(provider: P, queries: Q, unit_of_work: U) -> Self {
        Self {
            provider,
            queries,
            unit_of_work,
        }
    }
}

impl<P, Q, U> AddLocalLibraryRootHandler<P, Q, U>
where
    P: LocalFilesystemProvider,
    Q: LibraryRootQueries,
    U: UnitOfWorkFactory + Clone,
{
    /// Validates the selection, applies provider relationship semantics, and
    /// durably configures the root on success. Expected duplicate/overlap
    /// outcomes are non-mutating and record no events.
    pub fn handle<R>(
        &self,
        command: AddLocalLibraryRootCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<AddLocalLibraryRootResult, ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        let validated = self
            .provider
            .validate(command.selection())
            .map_err(|error| map_provider_error(context.trace_id(), error))?;
        let existing = self
            .queries
            .list_root_configurations(&context)
            .map_err(|error| map_persistence_error(context.trace_id(), error))?;
        for configuration in &existing {
            let relationship = self
                .provider
                .compare_roots(validated.locator(), configuration.locator());
            match relationship {
                RootRelationship::Same => {
                    return Ok(AddLocalLibraryRootResult::AlreadyConfigured(
                        configuration.root_id(),
                    ));
                }
                RootRelationship::Ancestor | RootRelationship::Descendant => {
                    return Ok(AddLocalLibraryRootResult::OverlapsExisting(
                        configuration.root_id(),
                        relationship,
                    ));
                }
                RootRelationship::Disjoint | RootRelationship::Unknown => {}
            }
        }

        let display_name = validated.display_name().to_owned();
        let safe_location = validated.safe_location_presentation().to_owned();
        let root_id = self
            .unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                let source_id = scope.library_source().ensure_local_filesystem_source()?;
                let root_id = scope.library_roots().insert(NewLibraryRoot::new(
                    source_id,
                    validated.locator().clone(),
                    validated.display_name().to_owned(),
                    validated.safe_location_presentation().to_owned(),
                    LibraryRootAvailability::Available,
                    1,
                ))?;
                recorder.record(ApplicationEvent::LibraryRootsChanged(LibraryRootsChanged))?;
                recorder.record(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                    library_root_id: root_id,
                }))?;
                scope.commit()?;
                Ok::<_, ApplicationPortError>(root_id)
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;

        Ok(AddLocalLibraryRootResult::Added(
            LibraryRootProjection::new(
                root_id,
                display_name,
                safe_location,
                LibraryRootAvailability::Available,
                None,
                None,
            ),
        ))
    }
}

/// Handles one transactional root removal.
pub struct RemoveLibraryRootHandler<U> {
    unit_of_work: U,
}

/// Handles one Add & Scan composite workflow with two durable boundaries.
pub struct AddLocalLibraryRootAndScanHandler<P, Q, U> {
    provider: P,
    queries: Q,
    unit_of_work: U,
}

impl<P, Q, U> AddLocalLibraryRootAndScanHandler<P, Q, U> {
    /// Composes the provider, query, and Unit of Work capabilities.
    pub const fn new(provider: P, queries: Q, unit_of_work: U) -> Self {
        Self {
            provider,
            queries,
            unit_of_work,
        }
    }
}

impl<P, Q, U> AddLocalLibraryRootAndScanHandler<P, Q, U>
where
    P: LocalFilesystemProvider + Clone,
    Q: LibraryRootQueries + Clone,
    U: UnitOfWorkFactory + Clone,
{
    /// Commits the root first, then requests child LibraryScan admission
    /// through the supplied runtime capability, then assembles the typed
    /// committed result. Child admission failure never rolls back or deletes
    /// the committed root and leaves no orphan background-operation state.
    pub fn handle<A, R>(
        &self,
        command: AddLocalLibraryRootAndScanCommand,
        context: OperationContext,
        admission: &A,
        recorder: R,
    ) -> Result<AddLocalLibraryRootAndScanResult, ApplicationError>
    where
        A: LibraryScanChildAdmission,
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        let add = AddLocalLibraryRootHandler::new(
            self.provider.clone(),
            self.queries.clone(),
            self.unit_of_work.clone(),
        )
        .handle(
            AddLocalLibraryRootCommand::new(command.selection().clone()),
            context.clone(),
            recorder,
        )?;
        match add {
            AddLocalLibraryRootResult::Added(root) => {
                let is_cancelled = Arc::new(|| false);
                match admission.admit(root.root_id(), &context, is_cancelled) {
                    Ok(result) => match result.outcome() {
                        StartLibraryScanResult::Admitted(handle) => {
                            Ok(AddLocalLibraryRootAndScanResult::AddedAndScanAdmitted(
                                root,
                                handle.clone(),
                            ))
                        }
                        StartLibraryScanResult::AlreadyScanning {
                            library_root_id,
                            active_job_run_id,
                            active_scan_run_id,
                        } => Ok(AddLocalLibraryRootAndScanResult::AddedButScanNotAdmitted(
                            root,
                            LibraryScanChildAdmissionIssue::AlreadyScanning {
                                library_root_id: *library_root_id,
                                active_job_run_id: *active_job_run_id,
                                active_scan_run_id: *active_scan_run_id,
                            },
                        )),
                    },
                    Err(error) => Ok(AddLocalLibraryRootAndScanResult::AddedButScanNotAdmitted(
                        root,
                        LibraryScanChildAdmissionIssue::AdmissionFailure(error),
                    )),
                }
            }
            AddLocalLibraryRootResult::AlreadyConfigured(root_id) => {
                Ok(AddLocalLibraryRootAndScanResult::AlreadyConfigured(root_id))
            }
            AddLocalLibraryRootResult::OverlapsExisting(root_id, relationship) => Ok(
                AddLocalLibraryRootAndScanResult::OverlapsExisting(root_id, relationship),
            ),
        }
    }
}

impl<U> RemoveLibraryRootHandler<U> {
    /// Composes the focused Unit of Work capability.
    pub const fn new(unit_of_work: U) -> Self {
        Self { unit_of_work }
    }
}

impl<U> RemoveLibraryRootHandler<U>
where
    U: UnitOfWorkFactory + Clone,
{
    /// Deletes current Argus root configuration only. The operation never
    /// touches user filesystem content and is idempotent for a missing root;
    /// invalidation events are recorded only for an actual removal.
    pub fn handle<R>(
        &self,
        command: RemoveLibraryRootCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<RemoveLibraryRootResult, ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        #[derive(Clone, Copy, Debug, Eq, PartialEq)]
        enum RemoveWork {
            Removed,
            RootHasActiveScan {
                job_run_id: JobRunId,
                scan_run_id: ScanRunId,
                owning_job_root_count: u32,
            },
        }
        let root_id = command.root_id();
        let work = self
            .unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                let ownership = {
                    let mut scan_runs = scope.scan_runs();
                    scan_runs.find_active_ownership(root_id)?
                };
                if let Some(ownership) = ownership {
                    scope.commit()?;
                    return Ok::<_, ApplicationPortError>(RemoveWork::RootHasActiveScan {
                        job_run_id: ownership.job_run_id(),
                        scan_run_id: ownership.scan_run_id(),
                        owning_job_root_count: ownership.owning_job_root_count(),
                    });
                }
                let deleted = scope.library_roots().delete(root_id)?;
                if deleted {
                    scope.source_entries().delete_for_root(root_id)?;
                }
                if deleted {
                    recorder.record(ApplicationEvent::LibraryRootsChanged(LibraryRootsChanged))?;
                    recorder.record(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                        library_root_id: root_id,
                    }))?;
                }
                scope.commit()?;
                Ok::<_, ApplicationPortError>(RemoveWork::Removed)
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;
        match work {
            RemoveWork::Removed => Ok(RemoveLibraryRootResult::Removed),
            RemoveWork::RootHasActiveScan {
                job_run_id,
                scan_run_id,
                owning_job_root_count,
            } => Ok(RemoveLibraryRootResult::RootHasActiveScan {
                library_root_id: root_id,
                job_run_id,
                scan_run_id,
                owning_job_root_count,
            }),
        }
    }
}

/// Handles one durable single-root scan admission.
pub struct StartLibraryScanHandler<Q, U> {
    queries: Q,
    unit_of_work: U,
}

impl<Q, U> StartLibraryScanHandler<Q, U> {
    /// Composes the root query and Unit of Work capabilities.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            queries,
            unit_of_work,
        }
    }
}

impl<Q, U> StartLibraryScanHandler<Q, U>
where
    Q: LibraryRootQueries,
    U: UnitOfWorkFactory + Clone,
{
    /// Validates the configured root, freezes the scan plan, enforces one
    /// active scan per root, and atomically establishes the durable
    /// JobRun/ScanRun admission state.
    pub fn handle<R>(
        &self,
        command: StartLibraryScanCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<LibraryScanAdmissionResult, ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        let root_id = command.root_id();
        let configuration = self
            .queries
            .get_scan_configuration(&context, root_id)
            .map_err(|error| map_persistence_error(context.trace_id(), error))?
            .ok_or_else(|| {
                application_error(
                    context.trace_id(),
                    ErrorCode::ConfigurationLibraryRootNotFound,
                )
            })?;
        let locator = configuration.locator().clone();
        let display_name = configuration.display_name().to_owned();
        let safe_location = configuration.safe_location_presentation().to_owned();
        let config_revision = configuration.config_revision();
        let source_config_revision = configuration.source_config_revision();
        let discovery_policy_revision = configuration.discovery_policy_revision();
        let created_at_ms = now_millis();
        let closure_locator = locator.clone();
        let closure_display_name = display_name.clone();
        let closure_safe_location = safe_location.clone();
        let admitted = self
            .unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                if !scope.library_roots().exists(root_id)? {
                    return Ok::<_, ApplicationPortError>(AdmissionWork::MissingRoot);
                }
                let ownership = {
                    let mut scan_runs = scope.scan_runs();
                    scan_runs.find_active_ownership(root_id)?
                };
                if let Some(ownership) = ownership {
                    return Ok::<_, ApplicationPortError>(AdmissionWork::AlreadyScanning {
                        active_job_run_id: ownership.job_run_id(),
                        active_scan_run_id: ownership.scan_run_id(),
                    });
                }
                let job_run_id = scope
                    .job_runs()
                    .insert(NewJobRun::new(OPERATION_TYPE_LIBRARY_SCAN, created_at_ms))?;
                scope.library_scan_admission_context().insert(
                    NewLibraryScanAdmissionContext::new(
                        job_run_id,
                        LibraryScanInvocationKind::InitialSingleRoot,
                        None,
                    ),
                )?;
                let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                    job_run_id,
                    root_id,
                    closure_locator,
                    &closure_display_name,
                    &closure_safe_location,
                    source_config_revision,
                    config_revision,
                    created_at_ms,
                ))?;
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job_run_id,
                        LibraryScanTargetKind::Requested,
                        root_id,
                        &closure_display_name,
                        &closure_safe_location,
                        None,
                        None,
                    ))?;
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job_run_id,
                        LibraryScanTargetKind::Admitted,
                        root_id,
                        &closure_display_name,
                        &closure_safe_location,
                        Some(scan_run_id),
                        None,
                    ))?;
                recorder.record(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                    library_root_id: root_id,
                }))?;
                recorder.record(ApplicationEvent::JobStateChanged(crate::JobStateChanged {
                    job_run_id,
                }))?;
                scope.commit()?;
                Ok::<_, ApplicationPortError>(AdmissionWork::Admitted {
                    job_run_id,
                    scan_run_id,
                })
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;

        match admitted {
            AdmissionWork::MissingRoot => Err(application_error(
                context.trace_id(),
                ErrorCode::ConfigurationLibraryRootNotFound,
            )),
            AdmissionWork::AlreadyScanning {
                active_job_run_id,
                active_scan_run_id,
            } => Ok(LibraryScanAdmissionResult::not_admitted(
                StartLibraryScanResult::AlreadyScanning {
                    library_root_id: root_id,
                    active_job_run_id,
                    active_scan_run_id,
                },
            )),
            AdmissionWork::Admitted {
                job_run_id,
                scan_run_id,
            } => {
                let plan = LibraryScanExecutionPlan::new(
                    root_id,
                    job_run_id,
                    scan_run_id,
                    locator,
                    display_name,
                    safe_location,
                    source_config_revision,
                    config_revision,
                    discovery_policy_revision,
                    created_at_ms,
                );
                let handle = OperationHandle::new(job_run_id, OPERATION_TYPE_LIBRARY_SCAN);
                let admitted = AdmittedScan::new(job_run_id, scan_run_id, plan);
                Ok(LibraryScanAdmissionResult::admitted(handle, admitted))
            }
        }
    }
}

/// Handles one durable multi-root Scan All admission.
pub struct StartLibraryScanAllHandler<Q, U> {
    queries: Q,
    unit_of_work: U,
}

impl<Q, U> StartLibraryScanAllHandler<Q, U> {
    /// Composes the root query and Unit of Work capabilities.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            queries,
            unit_of_work,
        }
    }
}

impl<Q, U> StartLibraryScanAllHandler<Q, U>
where
    Q: LibraryRootQueries,
    U: UnitOfWorkFactory + Clone,
{
    /// Snapshots the configured roots, validates them in canonical historical
    /// `LibraryRootId` ascending order, and atomically establishes one
    /// multi-root LibraryScan job when at least one root is eligible.
    pub fn handle<L, R>(
        &self,
        command: StartLibraryScanAllCommand,
        context: OperationContext,
        lookup: &L,
        recorder: R,
    ) -> Result<LibraryScanAllAdmissionResult, ApplicationError>
    where
        L: LibraryScanAllRequestLookup,
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        let trace_id = context.trace_id();
        if let Some(existing) = lookup.find_existing(&context, command.request_identity())? {
            return Ok(LibraryScanAllAdmissionResult::not_admitted(existing));
        }

        let mut configured_roots = self
            .queries
            .list_root_configurations(&context)
            .map_err(|error| map_persistence_error(trace_id, error))?;
        configured_roots.sort_by_key(|configuration| configuration.root_id());

        let created_at_ms = now_millis();
        let work = self
            .unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                #[derive(Clone)]
                struct EvaluatedScanAllTarget {
                    root_id: LibraryRootId,
                    locator: RootLocator,
                    display_name: String,
                    safe_location_display: String,
                    configuration: Option<LibraryRootScanConfiguration>,
                    exclusion: Option<LibraryScanAdmissionExclusion>,
                }

                let mut evaluations = Vec::with_capacity(configured_roots.len());
                for configured in &configured_roots {
                    let root_id = configured.root_id();
                    let exists = scope.library_roots().exists(root_id)?;
                    let configuration = if exists {
                        scope.library_roots().get_scan_authority(root_id)?
                    } else {
                        None
                    };
                    let active_owner = scope.scan_runs().find_active_ownership(root_id)?;

                    let (display_name, safe_location_display) =
                        if let Some(configuration) = configuration.as_ref() {
                            (
                                configuration.display_name().to_owned(),
                                configuration.safe_location_presentation().to_owned(),
                            )
                        } else {
                            (
                                root_id.to_string(),
                                configured.locator().as_provider_value().to_owned(),
                            )
                        };

                    let exclusion = if !exists {
                        Some(LibraryScanAdmissionExclusion::new(
                            root_id,
                            LibraryScanTargetExclusionReason::NoLongerConfigured,
                            None,
                            None,
                        ))
                    } else if configuration.is_none() {
                        Some(LibraryScanAdmissionExclusion::invalid_configuration(
                            root_id,
                            invalid_scan_all_configuration_error(trace_id),
                        ))
                    } else {
                        active_owner.map(|owner| {
                            LibraryScanAdmissionExclusion::new(
                                root_id,
                                LibraryScanTargetExclusionReason::AlreadyScanning,
                                Some(owner.job_run_id()),
                                Some(owner.scan_run_id()),
                            )
                        })
                    };

                    evaluations.push(EvaluatedScanAllTarget {
                        root_id,
                        locator: configured.locator().clone(),
                        display_name,
                        safe_location_display,
                        configuration,
                        exclusion,
                    });
                }

                let eligible_count = evaluations
                    .iter()
                    .filter(|evaluation| evaluation.exclusion.is_none())
                    .count();
                if eligible_count == 0 {
                    scope.commit()?;
                    return Ok::<_, ApplicationPortError>(ScanAllAdmissionWork::NothingEligible {
                        exclusions: evaluations
                            .iter()
                            .filter_map(|evaluation| evaluation.exclusion.clone())
                            .collect(),
                    });
                }

                let job_run_id = scope
                    .job_runs()
                    .insert(NewJobRun::new(OPERATION_TYPE_LIBRARY_SCAN, created_at_ms))?;
                scope.library_scan_admission_context().insert(
                    NewLibraryScanAdmissionContext::with_scan_all_request_identity(
                        job_run_id,
                        LibraryScanInvocationKind::InitialScanAll,
                        None,
                        command.request_identity().clone(),
                    ),
                )?;

                let mut admitted_plans = Vec::with_capacity(eligible_count);
                let mut admitted_root_ids = Vec::with_capacity(eligible_count);
                let mut exclusions = Vec::new();
                for evaluation in evaluations {
                    scope
                        .library_scan_targets()
                        .insert(NewLibraryScanTarget::new(
                            job_run_id,
                            LibraryScanTargetKind::Requested,
                            evaluation.root_id,
                            evaluation.display_name.clone(),
                            evaluation.safe_location_display.clone(),
                            None,
                            None,
                        ))?;
                    if let Some(exclusion) = evaluation.exclusion {
                        scope
                            .library_scan_targets()
                            .insert(NewLibraryScanTarget::new(
                                job_run_id,
                                LibraryScanTargetKind::Excluded,
                                evaluation.root_id,
                                evaluation.display_name,
                                evaluation.safe_location_display,
                                None,
                                Some(exclusion.clone()),
                            ))?;
                        exclusions.push(exclusion);
                        continue;
                    }

                    let configuration = evaluation
                        .configuration
                        .as_ref()
                        .expect("eligible Scan All target has a valid configuration");
                    let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                        job_run_id,
                        evaluation.root_id,
                        evaluation.locator,
                        evaluation.display_name.clone(),
                        evaluation.safe_location_display.clone(),
                        configuration.source_config_revision(),
                        configuration.config_revision(),
                        created_at_ms,
                    ))?;
                    scope
                        .library_scan_targets()
                        .insert(NewLibraryScanTarget::new(
                            job_run_id,
                            LibraryScanTargetKind::Admitted,
                            evaluation.root_id,
                            evaluation.display_name.clone(),
                            evaluation.safe_location_display.clone(),
                            Some(scan_run_id),
                            None,
                        ))?;
                    admitted_plans.push(LibraryScanExecutionPlan::new(
                        evaluation.root_id,
                        job_run_id,
                        scan_run_id,
                        configuration.locator().clone(),
                        evaluation.display_name,
                        evaluation.safe_location_display,
                        configuration.source_config_revision(),
                        configuration.config_revision(),
                        configuration.discovery_policy_revision(),
                        created_at_ms,
                    ));
                    admitted_root_ids.push(evaluation.root_id);
                    recorder.record(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                        library_root_id: evaluation.root_id,
                    }))?;
                }

                recorder.record(ApplicationEvent::JobStateChanged(crate::JobStateChanged {
                    job_run_id,
                }))?;
                scope.commit()?;
                Ok::<_, ApplicationPortError>(ScanAllAdmissionWork::Admitted {
                    job_run_id,
                    admitted_plans,
                    admitted_roots: admitted_root_ids,
                    exclusions,
                })
            })
            .map_err(|error| map_port_error(trace_id, error))?;

        match work {
            ScanAllAdmissionWork::NothingEligible { exclusions } => {
                Ok(LibraryScanAllAdmissionResult::not_admitted(
                    StartLibraryScanAllResult::NothingEligible { exclusions },
                ))
            }
            ScanAllAdmissionWork::Admitted {
                job_run_id,
                admitted_plans,
                admitted_roots,
                exclusions,
            } => {
                let handle = OperationHandle::new(job_run_id, OPERATION_TYPE_LIBRARY_SCAN);
                let admitted = AdmittedLibraryScanJob::new(job_run_id, admitted_plans);
                Ok(LibraryScanAllAdmissionResult::admitted(
                    handle,
                    admitted_roots,
                    exclusions,
                    admitted,
                ))
            }
        }
    }
}

#[derive(Debug)]
enum ScanAllAdmissionWork {
    NothingEligible {
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    },
    Admitted {
        job_run_id: JobRunId,
        admitted_plans: Vec<LibraryScanExecutionPlan>,
        admitted_roots: Vec<LibraryRootId>,
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum AdmissionWork {
    MissingRoot,
    AlreadyScanning {
        active_job_run_id: JobRunId,
        active_scan_run_id: ScanRunId,
    },
    Admitted {
        job_run_id: JobRunId,
        scan_run_id: ScanRunId,
    },
}

/// Thin application capability façade for library-root configuration.
pub struct LibraryService<Q, S, U, P> {
    queries: Q,
    source_entry_queries: S,
    unit_of_work: U,
    provider: P,
}

impl<Q, S, U, P> LibraryService<Q, S, U, P> {
    /// Composes the focused root query, source-entry query, Unit of Work, and
    /// provider ports.
    pub const fn new(queries: Q, source_entry_queries: S, unit_of_work: U, provider: P) -> Self {
        Self {
            queries,
            source_entry_queries,
            unit_of_work,
            provider,
        }
    }
}

impl<Q, S, U, P> LibraryService<Q, S, U, P>
where
    Q: LibraryRootQueries,
{
    /// Delegates the bounded authoritative root-list query.
    pub fn list_library_roots(
        &self,
        query: ListLibraryRootsQuery,
        context: OperationContext,
    ) -> Result<LibraryRootPage, ApplicationError> {
        self.queries
            .list(&context, query.offset(), query.page_size())
            .map_err(|error| map_persistence_error(context.trace_id(), error))
    }

    /// Delegates the authoritative root-detail query.
    pub fn get_library_root(
        &self,
        query: GetLibraryRootQuery,
        context: OperationContext,
    ) -> Result<LibraryRootProjection, ApplicationError> {
        self.queries
            .get(&context, query.root_id())
            .map_err(|error| map_persistence_error(context.trace_id(), error))?
            .ok_or_else(|| {
                application_error(
                    context.trace_id(),
                    ErrorCode::ConfigurationLibraryRootNotFound,
                )
            })
    }
}

impl<Q, S, U, P> LibraryService<Q, S, U, P>
where
    S: SourceEntryQueries,
{
    /// Delegates the bounded authoritative direct-child query.
    pub fn list_source_entry_children(
        &self,
        query: ListSourceEntryChildrenQuery,
        context: OperationContext,
    ) -> Result<SourceEntryChildrenPage, ApplicationError> {
        ListSourceEntryChildrenHandler::new(&self.source_entry_queries).handle(query, context)
    }

    /// Delegates the authoritative source-entry detail query.
    pub fn get_source_entry(
        &self,
        query: GetSourceEntryQuery,
        context: OperationContext,
    ) -> Result<SourceEntryDetailProjection, ApplicationError> {
        GetSourceEntryHandler::new(&self.source_entry_queries).handle(query, context)
    }
}

impl<Q, S, U, P> LibraryService<Q, S, U, P>
where
    Q: LibraryRootQueries + Clone,
    P: LocalFilesystemProvider + Clone,
    U: UnitOfWorkFactory + Clone,
{
    /// Delegates one root-only add operation.
    pub fn add_local_library_root<R>(
        &self,
        command: AddLocalLibraryRootCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<AddLocalLibraryRootResult, ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        self.add_handler().handle(command, context, recorder)
    }

    /// Executes the Add & Scan composite workflow through the supplied child
    /// LibraryScan admission capability.
    pub fn add_local_library_root_and_scan<A, R>(
        &self,
        command: AddLocalLibraryRootAndScanCommand,
        context: OperationContext,
        admission: &A,
        recorder: R,
    ) -> Result<AddLocalLibraryRootAndScanResult, ApplicationError>
    where
        A: LibraryScanChildAdmission,
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        AddLocalLibraryRootAndScanHandler::new(
            self.provider.clone(),
            self.queries.clone(),
            self.unit_of_work.clone(),
        )
        .handle(command, context, admission, recorder)
    }

    /// Replaces current native mounts and reconciles configured-root
    /// availability without scanning source contents or opening a write
    /// transaction during provider I/O.
    pub fn sync_local_filesystem_mounted_volumes<R>(
        &self,
        command: SyncLocalFilesystemMountedVolumesCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<(), ApplicationError>
    where
        P: LocalFilesystemBrowseProvider,
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        self.provider
            .replace_mounted_volumes(command.volumes())
            .map_err(|error| map_provider_error(context.trace_id(), error))?;
        let configurations = self
            .queries
            .list_root_configurations(&context)
            .map_err(|error| map_persistence_error(context.trace_id(), error))?;
        let mut changes = Vec::new();
        for configuration in configurations {
            let access = self
                .provider
                .open_access(configuration.locator())
                .map_err(|error| map_source_access_error(context.trace_id(), error))?;
            let availability = match access.resolve_root() {
                Ok(_) => LibraryRootAvailability::Available,
                Err(SourceAccessError::SourceUnavailable) => LibraryRootAvailability::Unavailable,
                Err(error) => {
                    return Err(map_source_access_error(context.trace_id(), error));
                }
            };
            if availability != configuration.availability() {
                changes.push((configuration.root_id(), availability));
            }
        }
        if changes.is_empty() {
            return Ok(());
        }

        self.unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                for (root_id, availability) in changes {
                    if scope
                        .library_roots()
                        .set_availability(root_id, availability)?
                    {
                        recorder.record(ApplicationEvent::LibraryRootChanged(
                            LibraryRootChanged {
                                library_root_id: root_id,
                            },
                        ))?;
                    }
                }
                scope.commit()?;
                Ok::<_, ApplicationPortError>(())
            })
            .map_err(|error| map_port_error(context.trace_id(), error))
    }

    /// Lists safe currently mounted browse roots through the provider port.
    pub fn list_local_filesystem_browse_roots(
        &self,
    ) -> Result<Vec<LocalFilesystemBrowseRoot>, ProviderError>
    where
        P: LocalFilesystemBrowseProvider,
    {
        self.provider.list_browse_roots()
    }

    /// Lists one bounded safe direct-child browse page through the provider.
    pub fn list_local_filesystem_browse_directories(
        &self,
        location: &LocalFilesystemBrowseLocation,
        cursor: Option<&LocalFilesystemBrowseCursor>,
        page_size: u32,
    ) -> Result<LocalFilesystemBrowsePage, ProviderError>
    where
        P: LocalFilesystemBrowseProvider,
    {
        self.provider
            .list_browse_directories(location, cursor, page_size)
    }

    /// Delegates one root-removal operation.
    pub fn remove_library_root<R>(
        &self,
        command: RemoveLibraryRootCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<RemoveLibraryRootResult, ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        RemoveLibraryRootHandler::new(self.unit_of_work.clone()).handle(command, context, recorder)
    }

    /// Admit one durable single-root library scan.
    pub fn start_library_scan<R>(
        &self,
        command: StartLibraryScanCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<LibraryScanAdmissionResult, ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        StartLibraryScanHandler::new(self.queries.clone(), self.unit_of_work.clone())
            .handle(command, context, recorder)
    }

    /// Admit one durable multi-root Scan All through the supplied request
    /// replay lookup. The lookup reconciles ambiguous transport before a
    /// fresh admission may be created.
    pub fn start_library_scan_all<L, R>(
        &self,
        command: StartLibraryScanAllCommand,
        context: OperationContext,
        lookup: &L,
        recorder: R,
    ) -> Result<LibraryScanAllAdmissionResult, ApplicationError>
    where
        L: LibraryScanAllRequestLookup,
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        StartLibraryScanAllHandler::new(self.queries.clone(), self.unit_of_work.clone())
            .handle(command, context, lookup, recorder)
    }

    /// Terminalizes an admitted run whose manager registration failed so no
    /// orphan nonterminal JobRun/ScanRun survives.
    pub fn fail_unregistered_scan<R>(
        &self,
        root_id: LibraryRootId,
        job_run_id: JobRunId,
        context: OperationContext,
        recorder: R,
    ) -> Result<(), ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        self.unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                let Some(ownership) = scope.scan_runs().find_active_ownership(root_id)? else {
                    scope.commit()?;
                    return Ok::<_, ApplicationPortError>(());
                };
                if ownership.job_run_id() != job_run_id {
                    scope.commit()?;
                    return Ok::<_, ApplicationPortError>(());
                }
                let timestamp_ms = now_millis();
                scope.scan_runs().set_status(
                    ownership.scan_run_id(),
                    crate::jobs::ScanRunStatus::Failed,
                    Some(timestamp_ms),
                    Some("admission_registration_failed".to_owned()),
                )?;
                scope
                    .job_runs()
                    .set_state(job_run_id, JobRunState::Failed, timestamp_ms)?;
                let summary = LibraryRootLastScanSummary::new(
                    ownership.scan_run_id().to_string(),
                    job_run_id.to_string(),
                    LibraryRootLastScanStatus::Failed,
                    timestamp_ms,
                    Some(timestamp_ms),
                );
                scope
                    .library_roots()
                    .set_last_scan(root_id, Some(summary))?;
                recorder.record(ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                    library_root_id: root_id,
                }))?;
                recorder.record(ApplicationEvent::JobStateChanged(crate::JobStateChanged {
                    job_run_id,
                }))?;
                scope.commit()?;
                Ok::<_, ApplicationPortError>(())
            })
            .map_err(|error| map_port_error(context.trace_id(), error))
    }

    fn add_handler(&self) -> AddLocalLibraryRootHandler<P, Q, U> {
        AddLocalLibraryRootHandler::new(
            self.provider.clone(),
            self.queries.clone(),
            self.unit_of_work.clone(),
        )
    }
}

fn map_port_error(trace_id: crate::TraceId, error: ApplicationPortError) -> ApplicationError {
    match error {
        ApplicationPortError::Persistence(error) => map_persistence_error(trace_id, error),
        ApplicationPortError::EventRecording => {
            application_error(trace_id, ErrorCode::InternalUnexpected)
        }
    }
}

fn map_provider_error(trace_id: crate::TraceId, error: ProviderError) -> ApplicationError {
    let code = match error {
        ProviderError::InvalidSelection
        | ProviderError::NotADirectory
        | ProviderError::LinkLikeRoot
        | ProviderError::Unavailable
        | ProviderError::InvalidBrowseRequest => ErrorCode::FilesystemInvalidRootSelection,
        ProviderError::PermissionDenied => ErrorCode::FilesystemPermissionDenied,
        ProviderError::Internal => ErrorCode::InternalUnexpected,
    };
    application_error(trace_id, code)
}

fn map_source_access_error(trace_id: crate::TraceId, error: SourceAccessError) -> ApplicationError {
    let code = match error {
        SourceAccessError::PermissionDenied | SourceAccessError::AuthorizationUnavailable => {
            ErrorCode::FilesystemPermissionDenied
        }
        SourceAccessError::SourceUnavailable => ErrorCode::FilesystemInvalidRootSelection,
        SourceAccessError::EntryNotFound
        | SourceAccessError::InvalidLocator
        | SourceAccessError::InvalidConfiguration
        | SourceAccessError::UnsupportedOperation
        | SourceAccessError::IoFailure
        | SourceAccessError::InvalidResponse
        | SourceAccessError::Cancelled => ErrorCode::InternalUnexpected,
    };
    application_error(trace_id, code)
}

pub(crate) fn application_error(trace_id: crate::TraceId, code: ErrorCode) -> ApplicationError {
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("sources error context follows the published catalog")
}

fn invalid_scan_all_configuration_error(trace_id: crate::TraceId) -> ApplicationError {
    let mut safe_context = SafeContext::new();
    safe_context
        .try_insert(
            SafeContextField::TechnicalClass,
            SafeContextValue::TechnicalClass(TechnicalClass::ConfigurationInvalid),
        )
        .expect("technical class is an allowed ConfigurationInvalid field");
    safe_context
        .try_insert(
            SafeContextField::FailureRole,
            SafeContextValue::FailureRole(FailureRole::Primary),
        )
        .expect("failure role is an allowed ConfigurationInvalid field");
    ApplicationError::from_code(ErrorCode::ConfigurationInvalid, trace_id, safe_context)
        .expect("scan all ConfigurationInvalid context follows the published catalog")
}

pub(crate) fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

pub(crate) fn map_persistence_error(
    trace_id: crate::TraceId,
    error: PersistenceError,
) -> ApplicationError {
    let code = match error {
        PersistenceError::PersistedSettingsInvalid(_) => {
            ErrorCode::ConfigurationPersistedSettingsInvalid
        }
        PersistenceError::DatabaseLocked => ErrorCode::PersistenceDatabaseLocked,
        PersistenceError::Cancelled => ErrorCode::OperationCancelled,
        PersistenceError::MigrationFailed => ErrorCode::PersistenceMigrationFailed,
        PersistenceError::CorruptOrIncompatible => ErrorCode::PersistenceIncompatibleSchema,
        PersistenceError::Unavailable
        | PersistenceError::ConstraintViolation
        | PersistenceError::Conflict
        | PersistenceError::Internal => ErrorCode::InternalUnexpected,
    };
    application_error(trace_id, code)
}
