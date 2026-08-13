//! Stable diagnostic contributor contracts owned by the application layer.

/// One already-sanitized diagnostic artifact.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DiagnosticArtifact {
    /// Stable archive-relative artifact name.
    pub name: String,
    /// Sanitized UTF-8 artifact bytes.
    pub contents: Vec<u8>,
}

/// Why a contributor could not produce its artifacts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticContributorError {
    /// The contributor's prerequisite capability was never initialized.
    Unavailable,
    /// Redaction policy rejected the produced content.
    RedactionViolation,
    /// A bounded I/O failure occurred while producing the artifact.
    Io,
}

/// One bounded, already-sanitized diagnostic source.
pub trait DiagnosticContributor: Send + Sync {
    /// Stable contributor identifier recorded in the manifest.
    fn id(&self) -> &'static str;

    /// Returns the contributor's sanitized artifacts.
    fn contribute(&self) -> Result<Vec<DiagnosticArtifact>, DiagnosticContributorError>;
}

/// Health state for one Phase 000 subsystem.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SubsystemHealthState {
    Healthy,
    Degraded,
    Unavailable,
}

/// One typed subsystem health observation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HealthSnapshot {
    /// Stable subsystem identifier.
    pub subsystem: &'static str,
    /// Current health state.
    pub state: SubsystemHealthState,
    /// Observation timestamp in milliseconds.
    pub observed_at_ms: i64,
    /// Operation trace that produced the observation.
    pub trace_id: crate::TraceId,
    /// Stable summary localization key.
    pub summary_key: &'static str,
    /// Bounded typed diagnostic context.
    pub context: crate::SafeContext,
}
