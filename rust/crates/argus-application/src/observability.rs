//! Application-owned correlation and startup-observability contracts.

use std::collections::BTreeMap;
use std::fmt;

/// The non-zero 128-bit identity assigned to one top-level operation.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct TraceId([u8; 16]);

/// The reason a trace identity cannot be constructed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TraceIdError {
    /// All-zero trace identities are reserved and invalid.
    Zero,
}

impl TryFrom<[u8; 16]> for TraceId {
    type Error = TraceIdError;

    fn try_from(value: [u8; 16]) -> Result<Self, Self::Error> {
        if value == [0; 16] {
            Err(TraceIdError::Zero)
        } else {
            Ok(Self(value))
        }
    }
}

impl TryFrom<u128> for TraceId {
    type Error = TraceIdError;

    fn try_from(value: u128) -> Result<Self, Self::Error> {
        Self::try_from(value.to_be_bytes())
    }
}

impl TraceId {
    /// Returns the canonical raw bytes for internal correlation propagation.
    pub fn as_bytes(self) -> [u8; 16] {
        self.0
    }
}

impl fmt::Display for TraceId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        for byte in self.0 {
            write!(formatter, "{byte:02x}")?;
        }
        Ok(())
    }
}

/// A stable, low-cardinality subsystem name.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SubsystemName(String);

/// A stable, low-cardinality operation name.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationName(String);

/// A stable dot-separated observability event name.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EventName(String);

/// The reason a stable observability name is invalid.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NameError {
    Invalid,
}

impl SubsystemName {
    /// Returns the stable serialized subsystem name.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl OperationName {
    /// Returns the stable serialized operation name.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl EventName {
    /// Returns the stable serialized event name.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<&str> for SubsystemName {
    type Error = NameError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        valid_lower_snake(value)
            .then(|| Self(value.into()))
            .ok_or(NameError::Invalid)
    }
}

impl TryFrom<&str> for OperationName {
    type Error = NameError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        valid_lower_snake(value)
            .then(|| Self(value.into()))
            .ok_or(NameError::Invalid)
    }
}

impl TryFrom<&str> for EventName {
    type Error = NameError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        valid_event_name(value)
            .then(|| Self(value.into()))
            .ok_or(NameError::Invalid)
    }
}

/// Operation identity propagated through application and persistence calls.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationContext {
    trace_id: TraceId,
    subsystem: SubsystemName,
    operation: OperationName,
}

impl OperationContext {
    /// Creates context for one top-level operation.
    pub fn new(trace_id: TraceId, subsystem: SubsystemName, operation: OperationName) -> Self {
        Self {
            trace_id,
            subsystem,
            operation,
        }
    }

    /// Returns the inherited operation trace identity.
    pub fn trace_id(&self) -> TraceId {
        self.trace_id
    }

    /// Returns the stable subsystem name.
    pub fn subsystem(&self) -> &SubsystemName {
        &self.subsystem
    }

    /// Returns the stable operation name.
    pub fn operation(&self) -> &OperationName {
        &self.operation
    }
}

/// Startup phases permitted in safe diagnostic context.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum DiagnosticStage {
    Environment,
    Observability,
    Persistence,
}

/// Logical application-data location classification.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum PathClass {
    StandardApplicationData,
    ExplicitOverride,
}

/// Migration outcomes permitted in startup diagnostics.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum MigrationOutcome {
    Applied,
    AlreadyCurrent,
}

/// Platform classification that contains no user path information.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum PlatformClass {
    Windows,
    MacOs,
    Unix,
}

/// CPU architecture classification that contains no machine-specific details.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum ArchitectureClass {
    X8664,
    Aarch64,
    X86,
    Arm,
    Unknown,
}

/// Bounded classification for technical failures.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum TechnicalClass {
    ConfigurationInvalid,
    FilesystemPermissionDenied,
    DatabaseOpenFailed,
    DatabaseLocked,
    MigrationFailed,
    IncompatibleSchema,
    Internal,
}

/// Settings bounded context permitted in persisted-settings diagnostics.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum SettingsDomain {
    Appearance,
}

/// Sanitized reason for a persisted settings integrity failure.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum PersistedSettingsReason {
    Missing,
    InvalidValue,
    MappingFailed,
}

/// Role of an error log in a top-level operation.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum FailureRole {
    Primary,
    Secondary,
}

/// A bounded version value suitable for safe diagnostic context.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct Version(String);

impl Version {
    /// Returns the validated version string.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<&str> for Version {
    type Error = SafeContextError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        if value.is_empty() || value.len() > SafeContext::MAX_STRING_BYTES {
            return Err(SafeContextError::ValueTooLong);
        }
        if !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'+' | b'-' | b'_'))
        {
            return Err(SafeContextError::InvalidValue);
        }
        let lowercase = value.to_ascii_lowercase();
        if [
            "password",
            "passwd",
            "secret",
            "token",
            "credential",
            "api_key",
            "apikey",
            "auth",
            "bearer",
            "private_key",
            "key",
            "select",
            "insert",
            "update",
            "delete",
            "pragma",
            "sqlite",
            "drop",
            "create",
            "alter",
        ]
        .iter()
        .any(|forbidden| lowercase.contains(forbidden))
        {
            return Err(SafeContextError::InvalidValue);
        }
        Ok(Self(value.into()))
    }
}

/// The closed vocabulary of startup/error fields.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum SafeContextField {
    Stage,
    PathClass,
    MigrationCount,
    SchemaVersion,
    MigrationOutcome,
    ApplicationVersion,
    BackendVersion,
    Platform,
    Architecture,
    TechnicalClass,
    FailureRole,
    SettingsDomain,
    PersistedSettingsReason,
}

impl SafeContextField {
    /// Every field authorized by the Phase 000 safe-context catalog.
    pub const ALL: [Self; 13] = [
        Self::Stage,
        Self::PathClass,
        Self::MigrationCount,
        Self::SchemaVersion,
        Self::MigrationOutcome,
        Self::ApplicationVersion,
        Self::BackendVersion,
        Self::Platform,
        Self::Architecture,
        Self::TechnicalClass,
        Self::FailureRole,
        Self::SettingsDomain,
        Self::PersistedSettingsReason,
    ];
}

/// A value whose variant determines the only field class it can populate.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SafeContextValue {
    Stage(DiagnosticStage),
    PathClass(PathClass),
    MigrationCount(u32),
    SchemaVersion(u32),
    MigrationOutcome(MigrationOutcome),
    ApplicationVersion(Version),
    BackendVersion(Version),
    Platform(PlatformClass),
    Architecture(ArchitectureClass),
    TechnicalClass(TechnicalClass),
    FailureRole(FailureRole),
    SettingsDomain(SettingsDomain),
    PersistedSettingsReason(PersistedSettingsReason),
}

/// A bounded typed map for safe diagnostics and presentation context.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct SafeContext(BTreeMap<SafeContextField, SafeContextValue>);

/// The reason a field/value pair cannot enter safe context.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SafeContextError {
    WrongValueType,
    DuplicateField,
    TooManyFields,
    InvalidValue,
    ValueTooLong,
}

impl SafeContext {
    /// Maximum fields in one published context.
    pub const MAX_FIELDS: usize = 32;
    /// Maximum UTF-8 byte count for a bounded version string.
    pub const MAX_STRING_BYTES: usize = 256;

    /// Creates an empty typed context.
    pub fn new() -> Self {
        Self::default()
    }

    /// Inserts one field exactly once after checking its declared value type.
    pub fn try_insert(
        &mut self,
        field: SafeContextField,
        value: SafeContextValue,
    ) -> Result<(), SafeContextError> {
        if !matches_field_value(field, &value) {
            return Err(SafeContextError::WrongValueType);
        }
        if self.0.contains_key(&field) {
            return Err(SafeContextError::DuplicateField);
        }
        if self.0.len() == Self::MAX_FIELDS {
            return Err(SafeContextError::TooManyFields);
        }
        self.0.insert(field, value);
        Ok(())
    }

    /// Returns one typed field when present.
    pub fn get(&self, field: &SafeContextField) -> Option<&SafeContextValue> {
        self.0.get(field)
    }

    /// Returns the number of fields currently present.
    pub fn len(&self) -> usize {
        self.0.len()
    }

    /// Returns whether no fields are present.
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// Iterates over the closed typed fields.
    pub fn iter(&self) -> impl Iterator<Item = (&SafeContextField, &SafeContextValue)> {
        self.0.iter()
    }
}

/// A structured diagnostic log record.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LogEvent {
    pub timestamp_ms: i64,
    pub level: LogLevel,
    pub context: OperationContext,
    pub event_name: EventName,
    pub fields: SafeContext,
    pub application_error: Option<crate::ApplicationError>,
}

impl LogEvent {
    /// Creates one explicit structured log record.
    pub fn new(
        timestamp_ms: i64,
        level: LogLevel,
        context: OperationContext,
        event_name: EventName,
        fields: SafeContext,
        application_error: Option<crate::ApplicationError>,
    ) -> Self {
        Self {
            timestamp_ms,
            level,
            context,
            event_name,
            fields,
            application_error,
        }
    }
}

/// Diagnostic importance used by structured log sinks.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

/// Execution phase recorded by a trace event.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TraceEventPhase {
    Started,
    Progress,
    Completed,
    Failed,
    Cancelled,
}

/// A structured execution trace record, separate from a log record.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TraceEvent {
    pub timestamp_ms: i64,
    pub context: OperationContext,
    pub event_name: EventName,
    pub phase: TraceEventPhase,
    pub fields: SafeContext,
    pub duration_ms: Option<u64>,
    pub error_code: Option<crate::ErrorCode>,
}

impl TraceEvent {
    /// Creates one explicit structured trace record.
    pub fn new(
        timestamp_ms: i64,
        context: OperationContext,
        event_name: EventName,
        phase: TraceEventPhase,
        fields: SafeContext,
        duration_ms: Option<u64>,
        error_code: Option<crate::ErrorCode>,
    ) -> Self {
        Self {
            timestamp_ms,
            context,
            event_name,
            phase,
            fields,
            duration_ms,
            error_code,
        }
    }
}

/// Failure from the bounded in-memory startup sink.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ObservabilitySinkError {
    CapacityExceeded,
}

/// Application-owned sink contract for the minimum startup diagnostics.
pub trait ObservabilitySink {
    /// Records a structured log without converting it from a trace.
    fn record_log(&mut self, event: LogEvent) -> Result<(), ObservabilitySinkError>;

    /// Records a structured trace independently from logs.
    fn record_trace(&mut self, event: TraceEvent) -> Result<(), ObservabilitySinkError>;
}

/// Bounded in-memory startup collector used when no external sink exists.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct StartupCollector {
    logs: Vec<LogEvent>,
    traces: Vec<TraceEvent>,
}

impl StartupCollector {
    /// Maximum records retained per stream.
    pub const MAX_RECORDS: usize = 64;

    /// Creates an empty collector.
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns logs in emission order.
    pub fn logs(&self) -> &[LogEvent] {
        &self.logs
    }

    /// Returns traces in emission order.
    pub fn traces(&self) -> &[TraceEvent] {
        &self.traces
    }
}

impl ObservabilitySink for StartupCollector {
    fn record_log(&mut self, event: LogEvent) -> Result<(), ObservabilitySinkError> {
        if self.logs.len() == Self::MAX_RECORDS {
            return Err(ObservabilitySinkError::CapacityExceeded);
        }
        self.logs.push(event);
        Ok(())
    }

    fn record_trace(&mut self, event: TraceEvent) -> Result<(), ObservabilitySinkError> {
        if self.traces.len() == Self::MAX_RECORDS {
            return Err(ObservabilitySinkError::CapacityExceeded);
        }
        self.traces.push(event);
        Ok(())
    }
}

fn matches_field_value(field: SafeContextField, value: &SafeContextValue) -> bool {
    matches!(
        (field, value),
        (SafeContextField::Stage, SafeContextValue::Stage(_))
            | (SafeContextField::PathClass, SafeContextValue::PathClass(_))
            | (
                SafeContextField::MigrationCount,
                SafeContextValue::MigrationCount(_)
            )
            | (
                SafeContextField::SchemaVersion,
                SafeContextValue::SchemaVersion(_)
            )
            | (
                SafeContextField::MigrationOutcome,
                SafeContextValue::MigrationOutcome(_)
            )
            | (
                SafeContextField::ApplicationVersion,
                SafeContextValue::ApplicationVersion(_)
            )
            | (
                SafeContextField::BackendVersion,
                SafeContextValue::BackendVersion(_)
            )
            | (SafeContextField::Platform, SafeContextValue::Platform(_))
            | (
                SafeContextField::Architecture,
                SafeContextValue::Architecture(_)
            )
            | (
                SafeContextField::TechnicalClass,
                SafeContextValue::TechnicalClass(_)
            )
            | (
                SafeContextField::FailureRole,
                SafeContextValue::FailureRole(_)
            )
            | (
                SafeContextField::SettingsDomain,
                SafeContextValue::SettingsDomain(_)
            )
            | (
                SafeContextField::PersistedSettingsReason,
                SafeContextValue::PersistedSettingsReason(_)
            )
    )
}

fn valid_lower_snake(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value.as_bytes()[0].is_ascii_lowercase()
        && !value.ends_with('_')
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_')
}

fn valid_event_name(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value.as_bytes()[0].is_ascii_lowercase()
        && !value.ends_with('.')
        && !value.contains("..")
        && value
            .split('.')
            .all(|segment| !segment.is_empty() && segment.as_bytes()[0].is_ascii_lowercase())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'.')
}
