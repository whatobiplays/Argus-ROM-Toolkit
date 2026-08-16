//! Runtime-owned diagnostic export orchestration over retained sanitized
//! failed-startup evidence and typed health snapshots.

use std::path::Path;

use argus_application::{
    ApplicationError, DiagnosticArtifact, DiagnosticContributor, DiagnosticContributorError,
    ErrorCode, HealthSnapshot, LogEvent, SafeContext, SubsystemHealthState,
};
use argus_infrastructure::diagnostics::DiagnosticZipWriter;

use crate::{
    DiagnosticsExport, DiagnosticsExportOutcome, FailedStartupDiagnostics, Platform,
    RuntimeInstanceId, architecture_class, now_millis, platform_class,
};

/// Exports the version-1 diagnostic bundle for a failed startup generation.
/// Export with injectable contributors for deterministic tests.
pub(crate) fn export_with_contributors(
    diagnostics: &FailedStartupDiagnostics,
    generation_id: RuntimeInstanceId,
    destination: &Path,
    trace_id: argus_application::TraceId,
    extra_contributors: Vec<Box<dyn DiagnosticContributor>>,
) -> Result<DiagnosticsExport, ApplicationError> {
    let mut contributors: Vec<Box<dyn DiagnosticContributor>> = vec![
        Box::new(RuntimeContributor {
            diagnostics,
            generation_id,
        }),
        Box::new(PersistenceContributor { diagnostics }),
        Box::new(HealthContributor {
            diagnostics,
            export_trace_id: trace_id,
        }),
        Box::new(ConfigurationContributor { diagnostics }),
    ];
    contributors.extend(extra_contributors);

    let mut writer = DiagnosticZipWriter::create(destination)
        .map_err(|_| diagnostics_error(trace_id, ErrorCode::InternalUnexpected))?;
    let mut included = Vec::new();
    let mut omitted = Vec::new();
    let mut contributor_failures = Vec::new();
    let mut partial = false;

    let mut artifacts = Vec::new();
    for contributor in &contributors {
        match contributor.contribute() {
            Ok(mut produced) => artifacts.append(&mut produced),
            Err(_) => {
                partial = true;
                contributor_failures.push(contributor.id());
                omitted.push(contributor.id());
            }
        }
    }

    for artifact in &artifacts {
        included.push(artifact.name.clone());
    }

    let manifest = manifest_json(trace_id, &included, &omitted, &contributor_failures);
    writer
        .add_artifact("manifest.json", manifest.as_bytes())
        .map_err(|_| diagnostics_error(trace_id, ErrorCode::InternalUnexpected))?;
    for artifact in &artifacts {
        writer
            .add_artifact(&artifact.name, &artifact.contents)
            .map_err(|_| diagnostics_error(trace_id, ErrorCode::InternalUnexpected))?;
    }
    writer
        .finish()
        .map_err(|_| diagnostics_error(trace_id, ErrorCode::InternalUnexpected))?;

    Ok(DiagnosticsExport {
        outcome: if partial {
            DiagnosticsExportOutcome::Partial
        } else {
            DiagnosticsExportOutcome::Created
        },
        destination_classification: "user_selected",
    })
}

struct RuntimeContributor<'a> {
    diagnostics: &'a FailedStartupDiagnostics,
    generation_id: RuntimeInstanceId,
}

impl DiagnosticContributor for RuntimeContributor<'_> {
    fn id(&self) -> &'static str {
        "runtime"
    }

    fn contribute(&self) -> Result<Vec<DiagnosticArtifact>, DiagnosticContributorError> {
        let mut logs = String::new();
        for log in self.diagnostics.collector.logs() {
            logs.push_str(&log_line(log));
            logs.push('\n');
        }
        Ok(vec![
            DiagnosticArtifact {
                name: "runtime.json".to_owned(),
                contents: format!(
                    "{{\"runtime_instance_id\":\"{}\",\"lifecycle\":\"startup_failed\",\"phase\":\"{}\",\"error_code\":\"{}\",\"trace_id\":\"{}\"}}",
                    self.generation_id,
                    phase_name(self.diagnostics.failure.phase),
                    self.diagnostics.failure.error.code.as_str(),
                    self.diagnostics.trace_id
                )
                .into_bytes(),
            },
            DiagnosticArtifact {
                name: "logs/argus.ndjson".to_owned(),
                contents: logs.into_bytes(),
            },
        ])
    }
}

struct PersistenceContributor<'a> {
    diagnostics: &'a FailedStartupDiagnostics,
}

impl DiagnosticContributor for PersistenceContributor<'_> {
    fn id(&self) -> &'static str {
        "persistence"
    }

    fn contribute(&self) -> Result<Vec<DiagnosticArtifact>, DiagnosticContributorError> {
        let contents = if let Some(summary) = &self.diagnostics.migration_summary {
            format!(
                "{{\"available\":true,\"schema_version\":{},\"applied_count\":{},\"migration_outcome\":\"{}\",\"location\":\"classified\"}}",
                summary.current_version,
                summary.applied_count,
                migration_outcome_name(summary.outcome)
            )
        } else {
            "{\"available\":false,\"location\":\"classified\"}".to_owned()
        };
        Ok(vec![DiagnosticArtifact {
            name: "persistence.json".to_owned(),
            contents: contents.into_bytes(),
        }])
    }
}

struct HealthContributor<'a> {
    diagnostics: &'a FailedStartupDiagnostics,
    export_trace_id: argus_application::TraceId,
}

impl DiagnosticContributor for HealthContributor<'_> {
    fn id(&self) -> &'static str {
        "health"
    }

    fn contribute(&self) -> Result<Vec<DiagnosticArtifact>, DiagnosticContributorError> {
        let observed_at_ms = now_millis();
        let snapshots = vec![
            HealthSnapshot {
                subsystem: "runtime",
                state: SubsystemHealthState::Unavailable,
                observed_at_ms,
                trace_id: self.export_trace_id,
                summary_key: "health.runtime.unavailable",
                context: SafeContext::new(),
            },
            HealthSnapshot {
                subsystem: "persistence",
                state: if self.diagnostics.migration_summary.is_some() {
                    SubsystemHealthState::Healthy
                } else {
                    SubsystemHealthState::Unavailable
                },
                observed_at_ms,
                trace_id: self.export_trace_id,
                summary_key: "health.persistence.initialized",
                context: SafeContext::new(),
            },
            HealthSnapshot {
                subsystem: "filesystem",
                state: if self.diagnostics.path_class.is_some() {
                    SubsystemHealthState::Healthy
                } else {
                    SubsystemHealthState::Unavailable
                },
                observed_at_ms,
                trace_id: self.export_trace_id,
                summary_key: "health.filesystem.data_directory_known",
                context: SafeContext::new(),
            },
        ];
        let contents = health_json(&snapshots);
        Ok(vec![DiagnosticArtifact {
            name: "health.json".to_owned(),
            contents: contents.into_bytes(),
        }])
    }
}

struct ConfigurationContributor<'a> {
    diagnostics: &'a FailedStartupDiagnostics,
}

impl DiagnosticContributor for ConfigurationContributor<'_> {
    fn id(&self) -> &'static str {
        "configuration"
    }

    fn contribute(&self) -> Result<Vec<DiagnosticArtifact>, DiagnosticContributorError> {
        let path_class = self
            .diagnostics
            .path_class
            .map(path_class_name)
            .unwrap_or("unavailable");
        Ok(vec![DiagnosticArtifact {
            name: "configuration.json".to_owned(),
            contents: format!(
                "{{\"path_class\":\"{}\",\"platform\":\"{}\",\"architecture\":\"{}\"}}",
                path_class,
                self.diagnostics
                    .platform
                    .map(platform_name)
                    .unwrap_or("unavailable"),
                self.diagnostics
                    .architecture
                    .map(architecture_name)
                    .unwrap_or("unavailable"),
            )
            .into_bytes(),
        }])
    }
}

fn manifest_json(
    trace_id: argus_application::TraceId,
    included: &[String],
    omitted: &[&str],
    contributor_failures: &[&str],
) -> String {
    let backend_version = crate::application_version();
    format!(
        "{{\"bundle_schema_version\":1,\"created_at\":{},\"application_version\":\"{}\",\"backend_version\":\"{}\",\"platform\":\"{}\",\"architecture\":\"{}\",\"trace_id\":\"{}\",\"included_artifacts\":{},\"omitted_artifacts\":{},\"contributor_failures\":{}}}",
        now_millis(),
        backend_version.as_str(),
        backend_version.as_str(),
        platform_name(platform_class(Platform::current())),
        architecture_name(architecture_class()),
        trace_id,
        json_string_list(included),
        json_string_list(
            &omitted
                .iter()
                .map(|value| value.to_string())
                .collect::<Vec<_>>()
        ),
        json_string_list(
            &contributor_failures
                .iter()
                .map(|value| value.to_string())
                .collect::<Vec<_>>(),
        ),
    )
}

fn health_json(snapshots: &[HealthSnapshot]) -> String {
    let entries = snapshots
        .iter()
        .map(|snapshot| {
            format!(
                "{{\"subsystem\":\"{}\",\"state\":\"{}\",\"observed_at_ms\":{},\"trace_id\":\"{}\",\"summary_key\":\"{}\",\"safe_context\":{}}}",
                snapshot.subsystem,
                health_state_name(snapshot.state),
                snapshot.observed_at_ms,
                snapshot.trace_id,
                snapshot.summary_key,
                safe_context_json(&snapshot.context)
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    format!("{{\"subsystems\":[{entries}]}}")
}

fn safe_context_json(context: &SafeContext) -> String {
    if context.is_empty() {
        return "{}".to_owned();
    }
    let entries = context
        .iter()
        .map(|(field, value)| {
            format!(
                "\"{}\":\"{}\"",
                safe_context_field_name(*field),
                safe_context_value_name(value)
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    format!("{{{entries}}}")
}

fn safe_context_field_name(field: argus_application::SafeContextField) -> &'static str {
    match field {
        argus_application::SafeContextField::Stage => "stage",
        argus_application::SafeContextField::PathClass => "path_class",
        argus_application::SafeContextField::MigrationCount => "migration_count",
        argus_application::SafeContextField::SchemaVersion => "schema_version",
        argus_application::SafeContextField::MigrationOutcome => "migration_outcome",
        argus_application::SafeContextField::ApplicationVersion => "application_version",
        argus_application::SafeContextField::BackendVersion => "backend_version",
        argus_application::SafeContextField::Platform => "platform",
        argus_application::SafeContextField::Architecture => "architecture",
        argus_application::SafeContextField::TechnicalClass => "technical_class",
        argus_application::SafeContextField::FailureRole => "failure_role",
        argus_application::SafeContextField::SettingsDomain => "settings_domain",
        argus_application::SafeContextField::PersistedSettingsReason => "persisted_settings_reason",
    }
}

fn safe_context_value_name(value: &argus_application::SafeContextValue) -> String {
    match value {
        argus_application::SafeContextValue::Stage(stage) => match stage {
            argus_application::DiagnosticStage::Environment => "environment".to_owned(),
            argus_application::DiagnosticStage::Observability => "observability".to_owned(),
            argus_application::DiagnosticStage::Persistence => "persistence".to_owned(),
        },
        argus_application::SafeContextValue::PathClass(value) => path_class_name(*value).to_owned(),
        argus_application::SafeContextValue::MigrationCount(value) => value.to_string(),
        argus_application::SafeContextValue::SchemaVersion(value) => value.to_string(),
        argus_application::SafeContextValue::MigrationOutcome(value) => {
            application_migration_outcome_name(*value).to_owned()
        }
        argus_application::SafeContextValue::ApplicationVersion(value) => value.as_str().to_owned(),
        argus_application::SafeContextValue::BackendVersion(value) => value.as_str().to_owned(),
        argus_application::SafeContextValue::Platform(value) => platform_name(*value).to_owned(),
        argus_application::SafeContextValue::Architecture(value) => {
            architecture_name(*value).to_owned()
        }
        argus_application::SafeContextValue::TechnicalClass(value) => match value {
            argus_application::TechnicalClass::ConfigurationInvalid => {
                "configuration_invalid".to_owned()
            }
            argus_application::TechnicalClass::FilesystemPermissionDenied => {
                "filesystem_permission_denied".to_owned()
            }
            argus_application::TechnicalClass::DatabaseOpenFailed => {
                "database_open_failed".to_owned()
            }
            argus_application::TechnicalClass::DatabaseLocked => "database_locked".to_owned(),
            argus_application::TechnicalClass::MigrationFailed => "migration_failed".to_owned(),
            argus_application::TechnicalClass::IncompatibleSchema => {
                "incompatible_schema".to_owned()
            }
            argus_application::TechnicalClass::Internal => "internal".to_owned(),
        },
        argus_application::SafeContextValue::FailureRole(value) => match value {
            argus_application::FailureRole::Primary => "primary".to_owned(),
            argus_application::FailureRole::Secondary => "secondary".to_owned(),
        },
        argus_application::SafeContextValue::SettingsDomain(value) => match value {
            argus_application::SettingsDomain::Appearance => "appearance".to_owned(),
        },
        argus_application::SafeContextValue::PersistedSettingsReason(value) => match value {
            argus_application::PersistedSettingsReason::Missing => "missing".to_owned(),
            argus_application::PersistedSettingsReason::InvalidValue => "invalid_value".to_owned(),
            argus_application::PersistedSettingsReason::MappingFailed => {
                "mapping_failed".to_owned()
            }
        },
    }
}

fn json_string_list(values: &[String]) -> String {
    let joined = values
        .iter()
        .map(|value| format!("\"{}\"", value))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{joined}]")
}

fn log_line(log: &LogEvent) -> String {
    format!(
        "{{\"timestamp_ms\":{},\"level\":\"{}\",\"event\":\"{}\",\"trace_id\":\"{}\"}}",
        log.timestamp_ms,
        log_level_name(log.level),
        log.event_name.as_str(),
        log.context.trace_id()
    )
}

fn diagnostics_error(trace_id: argus_application::TraceId, code: ErrorCode) -> ApplicationError {
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("diagnostics error uses an allowlisted empty context")
}

fn phase_name(phase: crate::StartupPhase) -> &'static str {
    phase.as_str()
}

fn log_level_name(level: argus_application::LogLevel) -> &'static str {
    match level {
        argus_application::LogLevel::Trace => "trace",
        argus_application::LogLevel::Debug => "debug",
        argus_application::LogLevel::Info => "info",
        argus_application::LogLevel::Warn => "warning",
        argus_application::LogLevel::Error => "error",
    }
}

fn migration_outcome_name(outcome: crate::KernelMigrationOutcome) -> &'static str {
    match outcome {
        crate::KernelMigrationOutcome::Applied => "applied",
        crate::KernelMigrationOutcome::AlreadyCurrent => "already_current",
    }
}

fn application_migration_outcome_name(
    outcome: argus_application::MigrationOutcome,
) -> &'static str {
    match outcome {
        argus_application::MigrationOutcome::Applied => "applied",
        argus_application::MigrationOutcome::AlreadyCurrent => "already_current",
    }
}

fn health_state_name(state: SubsystemHealthState) -> &'static str {
    match state {
        SubsystemHealthState::Healthy => "healthy",
        SubsystemHealthState::Degraded => "degraded",
        SubsystemHealthState::Unavailable => "unavailable",
    }
}

fn path_class_name(value: argus_application::PathClass) -> &'static str {
    match value {
        argus_application::PathClass::StandardApplicationData => "standard_application_data",
        argus_application::PathClass::ExplicitOverride => "explicit_override",
    }
}

fn platform_name(value: argus_application::PlatformClass) -> &'static str {
    match value {
        argus_application::PlatformClass::Windows => "windows",
        argus_application::PlatformClass::MacOs => "macos",
        argus_application::PlatformClass::Unix => "unix",
        argus_application::PlatformClass::Android => "android",
    }
}

fn architecture_name(value: argus_application::ArchitectureClass) -> &'static str {
    match value {
        argus_application::ArchitectureClass::X8664 => "x86_64",
        argus_application::ArchitectureClass::Aarch64 => "aarch64",
        argus_application::ArchitectureClass::X86 => "x86",
        argus_application::ArchitectureClass::Arm => "arm",
        argus_application::ArchitectureClass::Unknown => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use std::io::Read;

    use argus_application::{
        ApplicationError, ArchitectureClass, DiagnosticArtifact, DiagnosticContributor,
        DiagnosticContributorError, ErrorCode, EventName, LogEvent, LogLevel, ObservabilitySink,
        OperationContext, OperationName, PathClass, PlatformClass, SafeContext, SubsystemName,
    };

    use crate::{
        DiagnosticsExportOutcome, FailedStartupDiagnostics, KernelMigrationOutcome,
        KernelMigrationSummary, RecoveryAction, RecoveryActionKind, StartupFailure, StartupPhase,
        new_trace_id, now_millis,
    };

    use super::{export_with_contributors, health_json};

    fn diagnostics_fixture() -> FailedStartupDiagnostics {
        let trace_id = new_trace_id();
        let context = OperationContext::new(
            trace_id,
            SubsystemName::try_from("runtime").expect("subsystem"),
            OperationName::try_from("startup").expect("operation"),
        );
        let mut collector = argus_application::StartupCollector::new();
        collector
            .record_log(LogEvent::new(
                now_millis(),
                LogLevel::Info,
                context,
                EventName::try_from("runtime.startup.started").expect("event"),
                SafeContext::new(),
                None,
            ))
            .expect("log");
        let failure = StartupFailure {
            phase: StartupPhase::SettingsInitialization,
            error: ApplicationError::from_code(
                ErrorCode::ConfigurationPersistedSettingsInvalid,
                trace_id,
                SafeContext::new(),
            )
            .expect("error"),
            recovery_actions: vec![RecoveryAction {
                kind: RecoveryActionKind::ExportDiagnostics,
            }],
            diagnostics_available: true,
            data_directory_available: true,
        };
        FailedStartupDiagnostics {
            collector,
            migration_summary: Some(KernelMigrationSummary {
                applied_count: 0,
                current_version: 1,
                outcome: KernelMigrationOutcome::AlreadyCurrent,
            }),
            path_class: Some(PathClass::ExplicitOverride),
            platform: Some(PlatformClass::MacOs),
            architecture: Some(ArchitectureClass::Aarch64),
            trace_id,
            failure,
        }
    }

    struct FailingContributor;

    impl DiagnosticContributor for FailingContributor {
        fn id(&self) -> &'static str {
            "injected_failure"
        }

        fn contribute(&self) -> Result<Vec<DiagnosticArtifact>, DiagnosticContributorError> {
            Err(DiagnosticContributorError::Io)
        }
    }

    #[test]
    fn export_produces_full_bundle_with_retained_evidence() {
        let directory = tempfile::tempdir().expect("tempdir");
        let destination = directory.path().join("bundle.zip");
        let export_trace = new_trace_id();
        let export = export_with_contributors(
            &diagnostics_fixture(),
            crate::RuntimeInstanceId::new(),
            &destination,
            export_trace,
            Vec::new(),
        )
        .expect("export");
        assert_eq!(export.outcome, DiagnosticsExportOutcome::Created);

        let file = std::fs::File::open(destination).expect("archive");
        let mut archive = zip::ZipArchive::new(file).expect("zip");
        for name in [
            "manifest.json",
            "runtime.json",
            "logs/argus.ndjson",
            "persistence.json",
            "health.json",
            "configuration.json",
        ] {
            assert!(archive.by_name(name).is_ok(), "missing {name}");
        }
        let mut logs = String::new();
        archive
            .by_name("logs/argus.ndjson")
            .expect("logs")
            .read_to_string(&mut logs)
            .expect("read logs");
        assert!(!logs.is_empty(), "retained startup logs must be nonempty");
        let mut manifest = String::new();
        archive
            .by_name("manifest.json")
            .expect("manifest")
            .read_to_string(&mut manifest)
            .expect("read manifest");
        assert!(
            manifest.contains(&format!("\"trace_id\":\"{export_trace}\"")),
            "manifest must carry the export operation trace"
        );
    }

    #[test]
    fn noncritical_contributor_failure_produces_partial_bundle() {
        let directory = tempfile::tempdir().expect("tempdir");
        let destination = directory.path().join("partial.zip");
        let export = export_with_contributors(
            &diagnostics_fixture(),
            crate::RuntimeInstanceId::new(),
            &destination,
            new_trace_id(),
            vec![Box::new(FailingContributor)],
        )
        .expect("export");
        assert_eq!(export.outcome, DiagnosticsExportOutcome::Partial);

        let file = std::fs::File::open(destination).expect("archive");
        let mut archive = zip::ZipArchive::new(file).expect("zip");
        let mut manifest = String::new();
        archive
            .by_name("manifest.json")
            .expect("manifest")
            .read_to_string(&mut manifest)
            .expect("read manifest");
        assert!(manifest.contains("\"contributor_failures\":[\"injected_failure\"]"));
        assert!(manifest.contains("\"omitted_artifacts\":[\"injected_failure\"]"));
    }

    #[test]
    fn health_json_uses_stable_state_names() {
        let json = health_json(&[]);
        assert_eq!(json, "{\"subsystems\":[]}");
    }

    #[test]
    fn android_platform_class_serializes_to_bounded_value() {
        assert_eq!(super::platform_name(PlatformClass::Android), "android");
    }
}
