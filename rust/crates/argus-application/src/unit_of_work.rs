//! Consuming callback-scope transaction contracts owned by the application.

use crate::jobs::{
    JobRunRepository, LibraryScanAdmissionContextRepository, LibraryScanTargetRepository,
    ScanRunRepository, SourceEntryRepository,
};
use crate::settings::AppearanceSettingsRepository;
use crate::sources::{LibraryRootRepository, LibrarySourceRepository};
use crate::{ApplicationPortError, ArtworkRepository, MetadataRepository, OperationContext};

/// One active transaction scope.
pub trait UnitOfWork: Sized {
    /// The short-lived appearance repository view for this transaction.
    type AppearanceSettingsRepository<'scope>: AppearanceSettingsRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived internal library-source repository view.
    type LibrarySourceRepository<'scope>: LibrarySourceRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived configured-root repository view.
    type LibraryRootRepository<'scope>: LibraryRootRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived generic job-run repository view.
    type JobRunRepository<'scope>: JobRunRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived per-root scan-run repository view.
    type ScanRunRepository<'scope>: ScanRunRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived source-entry repository view.
    type SourceEntryRepository<'scope>: SourceEntryRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived library-scan admission-target repository view.
    type LibraryScanTargetRepository<'scope>: LibraryScanTargetRepository + 'scope
    where
        Self: 'scope;

    /// The short-lived LibraryScan admission-context repository view.
    type LibraryScanAdmissionContextRepository<'scope>: LibraryScanAdmissionContextRepository
        + 'scope
    where
        Self: 'scope;

    /// Borrows a typed appearance repository from the active transaction.
    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_>;

    /// Borrows a typed internal library-source repository.
    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_>;

    /// Borrows a typed configured-root repository.
    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_>;

    /// Borrows a typed generic job-run repository.
    fn job_runs(&mut self) -> Self::JobRunRepository<'_>;

    /// Borrows a typed per-root scan-run repository.
    fn scan_runs(&mut self) -> Self::ScanRunRepository<'_>;

    /// Borrows a typed source-entry repository.
    fn source_entries(&mut self) -> Self::SourceEntryRepository<'_>;

    /// Borrows a typed library-scan admission-target repository.
    fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_>;

    /// Borrows a typed LibraryScan admission-context repository.
    fn library_scan_admission_context(&mut self)
    -> Self::LibraryScanAdmissionContextRepository<'_>;

    /// Explicitly commits and consumes this scope.
    fn commit(self) -> Result<(), ApplicationPortError>;

    /// Explicitly rolls back and consumes this scope.
    fn rollback(self) -> Result<(), ApplicationPortError>;
}

/// Additive enrichment capability layered on the existing transaction scope.
///
/// Keeping this as a focused extension avoids forcing unrelated test doubles and
/// future persistence implementations to expose metadata/artwork repositories
/// before they support the enrichment slice.
pub trait EnrichmentUnitOfWork: UnitOfWork {
    /// Metadata persistence for this transaction.
    type MetadataRepository<'scope>: MetadataRepository + 'scope
    where
        Self: 'scope;

    /// Artwork persistence for this transaction.
    type ArtworkRepository<'scope>: ArtworkRepository + 'scope
    where
        Self: 'scope;

    /// Borrows the metadata repository from the active transaction.
    fn metadata(&mut self) -> Self::MetadataRepository<'_>;

    /// Borrows the artwork repository from the active transaction.
    fn artwork(&mut self) -> Self::ArtworkRepository<'_>;
}

/// Creates one transaction scope on the implementation's execution boundary.
///
/// The generic associated scope lifetime prevents a transaction-scoped value
/// from escaping the callback. The factory deliberately does not commit after
/// an `Ok` result: a callback that omits both terminal methods drops the scope
/// and therefore rolls it back.
///
/// ```compile_fail
/// use argus_application::{ApplicationPortError, OperationContext, UnitOfWork, UnitOfWorkFactory};
///
/// fn cannot_reuse_after_commit<F: UnitOfWorkFactory>(factory: &F, context: &OperationContext) {
///     let _ = factory.execute(context, |scope| {
///         let _ = scope.commit();
///         let _ = scope.rollback(); // the consuming commit moved `scope`
///         Ok::<(), ApplicationPortError>(())
///     });
/// }
/// ```
pub trait UnitOfWorkFactory {
    /// The implementation-owned transaction scope for one callback lifetime.
    type Scope<'scope>: UnitOfWork + 'scope
    where
        Self: 'scope;

    /// Executes one consuming transaction callback with the supplied context.
    fn execute<T, F>(
        &self,
        context: &OperationContext,
        operation: F,
    ) -> Result<T, ApplicationPortError>
    where
        T: Send + 'static,
        F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
            + Send
            + 'static;
}
