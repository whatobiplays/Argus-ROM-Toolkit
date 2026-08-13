//! The stable application error catalog used by the Phase 000 runtime.

use std::fmt;

use crate::{SafeContext, SafeContextField, TraceId};

/// Stable broad classifications used by the currently implemented Phase 000 catalog subset.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorCategory {
    Validation,
    Configuration,
    Filesystem,
    Persistence,
    Provider,
    Runtime,
    Operation,
    Internal,
}

/// Application impact independent of diagnostic log level.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ApplicationSeverity {
    Info,
    Warning,
    Error,
    Fatal,
}

/// Recovery precondition communicated by a published failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Recoverability {
    None,
    Retry,
    UserAction,
    RestartRequired,
    ManualIntervention,
}

/// Stable retry strategy communicated by a published failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RetryPolicy {
    Never,
    Immediate,
    Backoff,
    UserInitiated,
}

/// Stable localization key owned by the catalog.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MessageKey(&'static str);

impl MessageKey {
    /// Returns the stable dotted localization key.
    pub fn as_str(self) -> &'static str {
        self.0
    }
}

/// Published error codes currently implemented through Slice 003.
///
/// Later Phase 000 runtime, operation, and provider entries are intentionally
/// not represented until their owning slices are implemented.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorCode {
    ValidationInvalidArgument,
    ConfigurationInvalid,
    ConfigurationPersistedSettingsInvalid,
    FilesystemPermissionDenied,
    PersistenceDatabaseOpenFailed,
    PersistenceDatabaseLocked,
    PersistenceMigrationFailed,
    PersistenceIncompatibleSchema,
    InternalUnexpected,
    RuntimeNotReady,
    RuntimeStartupFailed,
    RuntimeShuttingDown,
    RuntimeStopped,
    RuntimeStaleInstance,
    RuntimeBridgeInitializationFailed,
    RuntimeCoreServiceInitializationFailed,
    OperationCancelled,
    InternalInvariantViolation,
}

/// Central policy metadata for one published code.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ErrorPolicy {
    pub category: ErrorCategory,
    pub severity: ApplicationSeverity,
    pub recoverability: Recoverability,
    pub retry_policy: RetryPolicy,
    pub message_key: MessageKey,
    pub allowed_context_fields: &'static [SafeContextField],
}

/// Failure while constructing an application error from a typed context.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ApplicationErrorError {
    DisallowedContextField(SafeContextField),
}

impl fmt::Display for ApplicationErrorError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DisallowedContextField(field) => {
                write!(
                    formatter,
                    "context field {field:?} is not allowed for this error"
                )
            }
        }
    }
}

impl std::error::Error for ApplicationErrorError {}

const COMMON_FAILURE_FIELDS: &[SafeContextField] = &[
    SafeContextField::Stage,
    SafeContextField::PathClass,
    SafeContextField::Platform,
    SafeContextField::Architecture,
    SafeContextField::TechnicalClass,
    SafeContextField::FailureRole,
];

const PERSISTENCE_FAILURE_FIELDS: &[SafeContextField] = &[
    SafeContextField::Stage,
    SafeContextField::PathClass,
    SafeContextField::Platform,
    SafeContextField::Architecture,
    SafeContextField::MigrationCount,
    SafeContextField::SchemaVersion,
    SafeContextField::MigrationOutcome,
    SafeContextField::ApplicationVersion,
    SafeContextField::BackendVersion,
    SafeContextField::TechnicalClass,
    SafeContextField::FailureRole,
];

const LOCKED_FAILURE_FIELDS: &[SafeContextField] = &[
    SafeContextField::Stage,
    SafeContextField::TechnicalClass,
    SafeContextField::FailureRole,
];

const SETTINGS_INTEGRITY_FIELDS: &[SafeContextField] = &[
    SafeContextField::SettingsDomain,
    SafeContextField::PersistedSettingsReason,
];

impl ErrorCode {
    /// Returns the currently implemented entries in stable catalog order.
    pub const fn all() -> &'static [Self; 9] {
        &[
            Self::ValidationInvalidArgument,
            Self::ConfigurationInvalid,
            Self::ConfigurationPersistedSettingsInvalid,
            Self::FilesystemPermissionDenied,
            Self::PersistenceDatabaseOpenFailed,
            Self::PersistenceDatabaseLocked,
            Self::PersistenceMigrationFailed,
            Self::PersistenceIncompatibleSchema,
            Self::InternalUnexpected,
        ]
    }

    /// Returns the complete catalog currently required by Phase 000.
    ///
    /// `all` intentionally retains its Slice 002/003 nine-entry shape for
    /// source compatibility. New callers should use this additive catalog.
    pub const fn phase_000_all() -> &'static [Self; 18] {
        &[
            Self::ValidationInvalidArgument,
            Self::ConfigurationInvalid,
            Self::ConfigurationPersistedSettingsInvalid,
            Self::PersistenceDatabaseOpenFailed,
            Self::PersistenceDatabaseLocked,
            Self::PersistenceMigrationFailed,
            Self::PersistenceIncompatibleSchema,
            Self::FilesystemPermissionDenied,
            Self::RuntimeBridgeInitializationFailed,
            Self::RuntimeCoreServiceInitializationFailed,
            Self::RuntimeNotReady,
            Self::RuntimeStartupFailed,
            Self::RuntimeShuttingDown,
            Self::RuntimeStopped,
            Self::RuntimeStaleInstance,
            Self::OperationCancelled,
            Self::InternalUnexpected,
            Self::InternalInvariantViolation,
        ]
    }

    /// Returns the permanent machine-readable code.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ValidationInvalidArgument => "ARGUS.V1.VALIDATION.INVALID_ARGUMENT",
            Self::ConfigurationInvalid => "ARGUS.V1.CONFIGURATION.INVALID",
            Self::ConfigurationPersistedSettingsInvalid => {
                "ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID"
            }
            Self::FilesystemPermissionDenied => "ARGUS.V1.FILESYSTEM.PERMISSION_DENIED",
            Self::PersistenceDatabaseOpenFailed => "ARGUS.V1.PERSISTENCE.DATABASE_OPEN_FAILED",
            Self::PersistenceDatabaseLocked => "ARGUS.V1.PERSISTENCE.DATABASE_LOCKED",
            Self::PersistenceMigrationFailed => "ARGUS.V1.PERSISTENCE.MIGRATION_FAILED",
            Self::PersistenceIncompatibleSchema => "ARGUS.V1.PERSISTENCE.INCOMPATIBLE_SCHEMA",
            Self::InternalUnexpected => "ARGUS.V1.INTERNAL.UNEXPECTED",
            Self::RuntimeNotReady => "ARGUS.V1.RUNTIME.NOT_READY",
            Self::RuntimeStartupFailed => "ARGUS.V1.RUNTIME.STARTUP_FAILED",
            Self::RuntimeShuttingDown => "ARGUS.V1.RUNTIME.SHUTTING_DOWN",
            Self::RuntimeStopped => "ARGUS.V1.RUNTIME.STOPPED",
            Self::RuntimeStaleInstance => "ARGUS.V1.RUNTIME.STALE_INSTANCE",
            Self::RuntimeBridgeInitializationFailed => {
                "ARGUS.V1.RUNTIME.BRIDGE_INITIALIZATION_FAILED"
            }
            Self::RuntimeCoreServiceInitializationFailed => {
                "ARGUS.V1.RUNTIME.CORE_SERVICE_INITIALIZATION_FAILED"
            }
            Self::OperationCancelled => "ARGUS.V1.OPERATION.CANCELLED",
            Self::InternalInvariantViolation => "ARGUS.V1.INTERNAL.INVARIANT_VIOLATION",
        }
    }

    /// Returns the centralized policy for this code.
    pub const fn policy(self) -> ErrorPolicy {
        match self {
            Self::ValidationInvalidArgument => policy(
                ErrorCategory::Validation,
                ApplicationSeverity::Warning,
                Recoverability::UserAction,
                RetryPolicy::Never,
                "errors.validation.invalid_argument",
                COMMON_FAILURE_FIELDS,
            ),
            Self::ConfigurationInvalid => policy(
                ErrorCategory::Configuration,
                ApplicationSeverity::Error,
                Recoverability::UserAction,
                RetryPolicy::Never,
                "errors.configuration.invalid",
                COMMON_FAILURE_FIELDS,
            ),
            Self::ConfigurationPersistedSettingsInvalid => policy(
                ErrorCategory::Configuration,
                ApplicationSeverity::Error,
                Recoverability::UserAction,
                RetryPolicy::UserInitiated,
                "errors.configuration.persisted_settings_invalid",
                SETTINGS_INTEGRITY_FIELDS,
            ),
            Self::FilesystemPermissionDenied => policy(
                ErrorCategory::Filesystem,
                ApplicationSeverity::Error,
                Recoverability::UserAction,
                RetryPolicy::UserInitiated,
                "errors.filesystem.permission_denied",
                COMMON_FAILURE_FIELDS,
            ),
            Self::PersistenceDatabaseOpenFailed => policy(
                ErrorCategory::Persistence,
                ApplicationSeverity::Error,
                Recoverability::Retry,
                RetryPolicy::Backoff,
                "errors.persistence.database_open_failed",
                COMMON_FAILURE_FIELDS,
            ),
            Self::PersistenceDatabaseLocked => policy(
                ErrorCategory::Persistence,
                ApplicationSeverity::Warning,
                Recoverability::Retry,
                RetryPolicy::Backoff,
                "errors.persistence.database_locked",
                LOCKED_FAILURE_FIELDS,
            ),
            Self::PersistenceMigrationFailed => policy(
                ErrorCategory::Persistence,
                ApplicationSeverity::Error,
                Recoverability::ManualIntervention,
                RetryPolicy::UserInitiated,
                "errors.persistence.migration_failed",
                PERSISTENCE_FAILURE_FIELDS,
            ),
            Self::PersistenceIncompatibleSchema => policy(
                ErrorCategory::Persistence,
                ApplicationSeverity::Error,
                Recoverability::ManualIntervention,
                RetryPolicy::Never,
                "errors.persistence.incompatible_schema",
                PERSISTENCE_FAILURE_FIELDS,
            ),
            Self::InternalUnexpected => policy(
                ErrorCategory::Internal,
                ApplicationSeverity::Error,
                Recoverability::ManualIntervention,
                RetryPolicy::Never,
                "errors.internal.unexpected",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeNotReady => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Warning,
                Recoverability::Retry,
                RetryPolicy::UserInitiated,
                "errors.runtime.not_ready",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeStartupFailed => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Error,
                Recoverability::RestartRequired,
                RetryPolicy::UserInitiated,
                "errors.runtime.startup_failed",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeShuttingDown => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Warning,
                Recoverability::RestartRequired,
                RetryPolicy::UserInitiated,
                "errors.runtime.shutting_down",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeStopped => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Warning,
                Recoverability::RestartRequired,
                RetryPolicy::UserInitiated,
                "errors.runtime.stopped",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeStaleInstance => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Warning,
                Recoverability::UserAction,
                RetryPolicy::Never,
                "errors.runtime.stale_instance",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeBridgeInitializationFailed => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Error,
                Recoverability::RestartRequired,
                RetryPolicy::UserInitiated,
                "errors.runtime.bridge_initialization_failed",
                COMMON_FAILURE_FIELDS,
            ),
            Self::RuntimeCoreServiceInitializationFailed => policy(
                ErrorCategory::Runtime,
                ApplicationSeverity::Error,
                Recoverability::RestartRequired,
                RetryPolicy::UserInitiated,
                "errors.runtime.core_service_initialization_failed",
                COMMON_FAILURE_FIELDS,
            ),
            Self::OperationCancelled => policy(
                ErrorCategory::Operation,
                ApplicationSeverity::Info,
                Recoverability::None,
                RetryPolicy::Never,
                "errors.operation.cancelled",
                COMMON_FAILURE_FIELDS,
            ),
            Self::InternalInvariantViolation => policy(
                ErrorCategory::Internal,
                ApplicationSeverity::Fatal,
                Recoverability::RestartRequired,
                RetryPolicy::Never,
                "errors.internal.invariant_violation",
                COMMON_FAILURE_FIELDS,
            ),
        }
    }
}

/// The only stable cross-application failure envelope in this slice.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ApplicationError {
    pub code: ErrorCode,
    pub category: ErrorCategory,
    pub severity: ApplicationSeverity,
    pub recoverability: Recoverability,
    pub retry_policy: RetryPolicy,
    pub message_key: MessageKey,
    pub trace_id: TraceId,
    pub safe_context: SafeContext,
}

impl ApplicationError {
    /// Builds an envelope only when every field is authorized by its catalog entry.
    pub fn from_code(
        code: ErrorCode,
        trace_id: TraceId,
        safe_context: SafeContext,
    ) -> Result<Self, ApplicationErrorError> {
        let policy = code.policy();
        for field in safe_context.iter().map(|(field, _)| *field) {
            if !policy.allowed_context_fields.contains(&field) {
                return Err(ApplicationErrorError::DisallowedContextField(field));
            }
        }
        Ok(Self {
            code,
            category: policy.category,
            severity: policy.severity,
            recoverability: policy.recoverability,
            retry_policy: policy.retry_policy,
            message_key: policy.message_key,
            trace_id,
            safe_context,
        })
    }
}

/// Stable persistence-port categories required by this slice.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PersistenceError {
    Unavailable,
    DatabaseLocked,
    Cancelled,
    ConstraintViolation,
    Conflict,
    CorruptOrIncompatible,
    MigrationFailed,
    PersistedSettingsInvalid(crate::PersistedSettingsReason),
    Internal,
}

impl PersistenceError {
    /// Returns the persistence category.
    pub const fn category(self) -> ErrorCategory {
        ErrorCategory::Persistence
    }
}

/// Technology-neutral failure returned across an application capability callback.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ApplicationPortError {
    Persistence(PersistenceError),
    EventRecording,
}

impl From<PersistenceError> for ApplicationPortError {
    fn from(error: PersistenceError) -> Self {
        Self::Persistence(error)
    }
}

const fn policy(
    category: ErrorCategory,
    severity: ApplicationSeverity,
    recoverability: Recoverability,
    retry_policy: RetryPolicy,
    message_key: &'static str,
    allowed_context_fields: &'static [SafeContextField],
) -> ErrorPolicy {
    ErrorPolicy {
        category,
        severity,
        recoverability,
        retry_policy,
        message_key: MessageKey(message_key),
        allowed_context_fields,
    }
}
