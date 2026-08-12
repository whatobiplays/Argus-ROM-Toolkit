//! The exact seven-code Slice 002 application error catalog.

use std::fmt;

use crate::{SafeContext, SafeContextField, TraceId};

/// Stable broad classifications used by the Slice 002 catalog.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorCategory {
    Configuration,
    Filesystem,
    Persistence,
    Internal,
}

/// Application impact independent of diagnostic log level.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ApplicationSeverity {
    Warning,
    Error,
}

/// Recovery precondition communicated by a published failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Recoverability {
    Retry,
    UserAction,
    ManualIntervention,
}

/// Stable retry strategy communicated by a published failure.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RetryPolicy {
    Never,
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

/// The only published error codes authorized by Slice 002.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ErrorCode {
    ConfigurationInvalid,
    FilesystemPermissionDenied,
    PersistenceDatabaseOpenFailed,
    PersistenceDatabaseLocked,
    PersistenceMigrationFailed,
    PersistenceIncompatibleSchema,
    InternalUnexpected,
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

impl ErrorCode {
    /// Returns all seven codes in stable catalog order.
    pub const fn all() -> &'static [Self; 7] {
        &[
            Self::ConfigurationInvalid,
            Self::FilesystemPermissionDenied,
            Self::PersistenceDatabaseOpenFailed,
            Self::PersistenceDatabaseLocked,
            Self::PersistenceMigrationFailed,
            Self::PersistenceIncompatibleSchema,
            Self::InternalUnexpected,
        ]
    }

    /// Returns the permanent machine-readable code.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ConfigurationInvalid => "ARGUS.V1.CONFIGURATION.INVALID",
            Self::FilesystemPermissionDenied => "ARGUS.V1.FILESYSTEM.PERMISSION_DENIED",
            Self::PersistenceDatabaseOpenFailed => "ARGUS.V1.PERSISTENCE.DATABASE_OPEN_FAILED",
            Self::PersistenceDatabaseLocked => "ARGUS.V1.PERSISTENCE.DATABASE_LOCKED",
            Self::PersistenceMigrationFailed => "ARGUS.V1.PERSISTENCE.MIGRATION_FAILED",
            Self::PersistenceIncompatibleSchema => "ARGUS.V1.PERSISTENCE.INCOMPATIBLE_SCHEMA",
            Self::InternalUnexpected => "ARGUS.V1.INTERNAL.UNEXPECTED",
        }
    }

    /// Returns the centralized policy for this code.
    pub const fn policy(self) -> ErrorPolicy {
        match self {
            Self::ConfigurationInvalid => policy(
                ErrorCategory::Configuration,
                ApplicationSeverity::Error,
                Recoverability::UserAction,
                RetryPolicy::Never,
                "errors.configuration.invalid",
                COMMON_FAILURE_FIELDS,
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
    ConstraintViolation,
    Conflict,
    CorruptOrIncompatible,
    MigrationFailed,
    Internal,
}

impl PersistenceError {
    /// Returns the persistence category.
    pub const fn category(self) -> ErrorCategory {
        ErrorCategory::Persistence
    }
}

/// Technology-neutral failure returned by a Phase 000 persistence port.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ApplicationPortError {
    Persistence(PersistenceError),
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
