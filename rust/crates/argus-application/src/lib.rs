//! Technology-neutral contracts for Argus application use cases and ports.
//!
//! This crate defines the stable vocabulary shared by runtime composition,
//! application handlers, and infrastructure adapters. It intentionally does not
//! expose persistence-driver, bridge, filesystem, or asynchronous-runtime types.

mod errors;
mod observability;
mod unit_of_work;

pub use errors::{
    ApplicationError, ApplicationErrorError, ApplicationPortError, ApplicationSeverity,
    ErrorCategory, ErrorCode, ErrorPolicy, MessageKey, PersistenceError, Recoverability,
    RetryPolicy,
};
pub use observability::{
    ArchitectureClass, DiagnosticStage, EventName, FailureRole, LogEvent, LogLevel,
    MigrationOutcome, NameError, ObservabilitySink, ObservabilitySinkError, OperationContext,
    OperationName, PathClass, PlatformClass, SafeContext, SafeContextError, SafeContextField,
    SafeContextValue, StartupCollector, SubsystemName, TechnicalClass, TraceEvent, TraceEventPhase,
    TraceId, TraceIdError, Version,
};
pub use unit_of_work::{UnitOfWork, UnitOfWorkFactory};
