//! Consuming callback-scope transaction contracts owned by the application.

use crate::settings::AppearanceSettingsRepository;
use crate::sources::{LibraryRootRepository, LibrarySourceRepository};
use crate::{ApplicationPortError, OperationContext};

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

    /// Borrows a typed appearance repository from the active transaction.
    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_>;

    /// Borrows a typed internal library-source repository.
    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_>;

    /// Borrows a typed configured-root repository.
    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_>;

    /// Explicitly commits and consumes this scope.
    fn commit(self) -> Result<(), ApplicationPortError>;

    /// Explicitly rolls back and consumes this scope.
    fn rollback(self) -> Result<(), ApplicationPortError>;
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
