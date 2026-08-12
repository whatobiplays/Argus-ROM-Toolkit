//! Technology-neutral contracts for Argus application use cases and ports.
//!
//! This crate defines the stable vocabulary shared by runtime composition,
//! application handlers, and infrastructure adapters. It intentionally does not
//! expose persistence-driver, bridge, filesystem, or asynchronous-runtime types.

mod errors;
mod events;
mod observability;
mod settings;
mod unit_of_work;

pub use argus_domain::{AppearanceSettings, ThemeMode, ThemeModeParseError};
pub use errors::{
    ApplicationError, ApplicationErrorError, ApplicationPortError, ApplicationSeverity,
    ErrorCategory, ErrorCode, ErrorPolicy, MessageKey, PersistenceError, Recoverability,
    RetryPolicy,
};
pub use events::{
    AppearanceSettingsChanged, AppearanceSettingsSubscriber, ApplicationEvent, EventRecorder,
    EventRecordingError, EventSubscriberError,
};
pub use observability::{
    ArchitectureClass, DiagnosticStage, EventName, FailureRole, LogEvent, LogLevel,
    MigrationOutcome, NameError, ObservabilitySink, ObservabilitySinkError, OperationContext,
    OperationName, PathClass, PersistedSettingsReason, PlatformClass, SafeContext,
    SafeContextError, SafeContextField, SafeContextValue, SettingsDomain, StartupCollector,
    SubsystemName, TechnicalClass, TraceEvent, TraceEventPhase, TraceId, TraceIdError, Version,
};
pub use settings::{
    AppearanceSettingsQueries, AppearanceSettingsRepository, GetAppearanceSettingsHandler,
    GetAppearanceSettingsQuery, SettingsService, UpdateAppearanceSettingsCommand,
    UpdateAppearanceSettingsHandler,
};
pub use unit_of_work::{UnitOfWork, UnitOfWorkFactory};
