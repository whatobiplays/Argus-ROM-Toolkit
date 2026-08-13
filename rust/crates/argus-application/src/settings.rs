//! Appearance-settings ports and focused application capabilities.

use argus_domain::AppearanceSettings;
use std::sync::Arc;

use crate::{
    ApplicationError, ApplicationEvent, ApplicationPortError, ErrorCode, EventRecorder,
    OperationContext, PersistenceError, SafeContext, SafeContextField, SafeContextValue,
    SettingsDomain, UnitOfWork, UnitOfWorkFactory,
};

/// Transaction-bound appearance-settings repository contract.
pub trait AppearanceSettingsRepository {
    /// Loads the current aggregate from the active transaction.
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError>;

    /// Replaces the complete aggregate inside the active transaction.
    fn save(&mut self, settings: &AppearanceSettings) -> Result<(), PersistenceError>;
}

/// Independent authoritative appearance-settings query contract.
pub trait AppearanceSettingsQueries {
    /// Reads the aggregate without opening a mutation Unit of Work.
    fn get(&self, context: &OperationContext) -> Result<AppearanceSettings, PersistenceError>;
}

/// Parameterless authoritative appearance read request.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct GetAppearanceSettingsQuery;

/// Complete desired appearance aggregate for one update operation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct UpdateAppearanceSettingsCommand {
    /// The replacement aggregate validated by the domain type.
    pub settings: AppearanceSettings,
}

impl UpdateAppearanceSettingsCommand {
    /// Creates a command from a complete valid aggregate.
    pub const fn new(settings: AppearanceSettings) -> Self {
        Self { settings }
    }
}

/// Handles one independent authoritative appearance read.
pub struct GetAppearanceSettingsHandler<Q> {
    queries: Q,
}

impl<Q> GetAppearanceSettingsHandler<Q> {
    /// Composes the focused query capability without a transaction capability.
    pub const fn new(queries: Q) -> Self {
        Self { queries }
    }
}

impl<Q> GetAppearanceSettingsHandler<Q>
where
    Q: AppearanceSettingsQueries,
{
    /// Executes the parameterless authoritative appearance query.
    pub fn handle(
        &self,
        _query: GetAppearanceSettingsQuery,
        context: OperationContext,
    ) -> Result<AppearanceSettings, ApplicationError> {
        self.queries
            .get(&context)
            .map_err(|error| map_persistence_error(context.trace_id(), error))
    }
}

/// Handles one complete-aggregate transactional appearance update.
pub struct UpdateAppearanceSettingsHandler<U> {
    unit_of_work: U,
}

impl<U> UpdateAppearanceSettingsHandler<U> {
    /// Composes the focused Unit of Work capability.
    pub const fn new(unit_of_work: U) -> Self {
        Self { unit_of_work }
    }
}

impl<U> UpdateAppearanceSettingsHandler<U>
where
    U: UnitOfWorkFactory + Clone,
{
    /// Executes the semantic update and records its event before commit.
    pub fn handle<R>(
        &self,
        command: UpdateAppearanceSettingsCommand,
        context: OperationContext,
        recorder: R,
        pre_commit: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<(), ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        let requested = command.settings;
        self.unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                let changed = {
                    let mut repository = scope.appearance_settings();
                    let current = repository.get()?;
                    if current == requested {
                        false
                    } else {
                        repository.save(&requested)?;
                        true
                    }
                };
                if changed {
                    recorder.record(ApplicationEvent::AppearanceSettingsChanged(
                        crate::AppearanceSettingsChanged,
                    ))?;
                }
                if pre_commit() {
                    return Err(ApplicationPortError::Persistence(
                        PersistenceError::Cancelled,
                    ));
                }
                scope.commit()?;
                Ok::<_, ApplicationPortError>(())
            })
            .map_err(|error| map_port_error(context.trace_id(), error))
    }
}

/// Thin application capability façade for appearance settings.
pub struct SettingsService<Q, U> {
    get_handler: GetAppearanceSettingsHandler<Q>,
    update_handler: UpdateAppearanceSettingsHandler<U>,
}

impl<Q, U> SettingsService<Q, U> {
    /// Composes the two focused appearance operation handlers.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            get_handler: GetAppearanceSettingsHandler::new(queries),
            update_handler: UpdateAppearanceSettingsHandler::new(unit_of_work),
        }
    }
}

impl<Q, U> SettingsService<Q, U>
where
    Q: AppearanceSettingsQueries,
{
    /// Delegates the independent authoritative appearance read.
    pub fn get_appearance_settings(
        &self,
        query: GetAppearanceSettingsQuery,
        context: OperationContext,
    ) -> Result<AppearanceSettings, ApplicationError> {
        self.get_handler.handle(query, context)
    }
}

impl<Q, U> SettingsService<Q, U>
where
    U: UnitOfWorkFactory + Clone,
{
    /// Delegates one complete-aggregate transactional appearance update.
    pub fn update_appearance_settings<R>(
        &self,
        command: UpdateAppearanceSettingsCommand,
        context: OperationContext,
        recorder: R,
        pre_commit: Arc<dyn Fn() -> bool + Send + Sync>,
    ) -> Result<(), ApplicationError>
    where
        R: EventRecorder + Clone + Send + Sync + 'static,
    {
        self.update_handler
            .handle(command, context, recorder, pre_commit)
    }
}

fn map_port_error(trace_id: crate::TraceId, error: ApplicationPortError) -> ApplicationError {
    match error {
        ApplicationPortError::Persistence(error) => map_persistence_error(trace_id, error),
        ApplicationPortError::EventRecording => {
            application_error(trace_id, ErrorCode::InternalUnexpected, SafeContext::new())
        }
    }
}

fn map_persistence_error(trace_id: crate::TraceId, error: PersistenceError) -> ApplicationError {
    let (code, context) = match error {
        PersistenceError::PersistedSettingsInvalid(reason) => {
            let mut context = SafeContext::new();
            insert(
                &mut context,
                SafeContextField::SettingsDomain,
                SafeContextValue::SettingsDomain(SettingsDomain::Appearance),
            );
            insert(
                &mut context,
                SafeContextField::PersistedSettingsReason,
                SafeContextValue::PersistedSettingsReason(reason),
            );
            (ErrorCode::ConfigurationPersistedSettingsInvalid, context)
        }
        PersistenceError::DatabaseLocked => {
            (ErrorCode::PersistenceDatabaseLocked, SafeContext::new())
        }
        PersistenceError::Cancelled => (ErrorCode::OperationCancelled, SafeContext::new()),
        PersistenceError::MigrationFailed => {
            (ErrorCode::PersistenceMigrationFailed, SafeContext::new())
        }
        PersistenceError::CorruptOrIncompatible => {
            (ErrorCode::PersistenceIncompatibleSchema, SafeContext::new())
        }
        PersistenceError::Unavailable
        | PersistenceError::ConstraintViolation
        | PersistenceError::Conflict
        | PersistenceError::Internal => (ErrorCode::InternalUnexpected, SafeContext::new()),
    };
    application_error(trace_id, code, context)
}

fn application_error(
    trace_id: crate::TraceId,
    code: ErrorCode,
    context: SafeContext,
) -> ApplicationError {
    ApplicationError::from_code(code, trace_id, context)
        .expect("settings error context follows the published catalog")
}

fn insert(context: &mut SafeContext, field: SafeContextField, value: SafeContextValue) {
    context
        .try_insert(field, value)
        .expect("settings error context is unique and type-safe");
}
