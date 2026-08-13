//! Bounded failed-runtime recovery capabilities retained after startup
//! cleanup. The normal Ready service graph is never retained here.

use std::path::PathBuf;

use argus_application::{
    ApplicationError, ArchitectureClass, OperationContext, PathClass, PlatformClass,
    StartupCollector,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;

use crate::{KernelMigrationSummary, StartupFailure, TraceId};

/// Narrow executor capable of the targeted appearance reset transaction.
pub(crate) struct AppearanceResetCapability {
    executor: SqliteDatabaseExecutor,
}

impl AppearanceResetCapability {
    /// Wraps a persistence executor retained after cleanup.
    pub(crate) fn new(executor: SqliteDatabaseExecutor) -> Self {
        Self { executor }
    }

    /// Runs the atomic appearance-only reset under a fresh recovery trace.
    pub(crate) fn reset(&self, context: &OperationContext) -> Result<(), ApplicationError> {
        crate::reset_appearance_with_executor(&self.executor, context)
    }
}

/// Bounded sanitized failed-startup diagnostic snapshot.
pub(crate) struct FailedStartupDiagnostics {
    pub(crate) collector: StartupCollector,
    pub(crate) migration_summary: Option<KernelMigrationSummary>,
    pub(crate) path_class: Option<PathClass>,
    pub(crate) platform: Option<PlatformClass>,
    pub(crate) architecture: Option<ArchitectureClass>,
    pub(crate) trace_id: TraceId,
    pub(crate) failure: StartupFailure,
}

/// Capabilities that remain genuinely safe after a failed startup.
pub(crate) struct FailedRuntimeRecoveryContext {
    pub(crate) appearance_reset: Option<AppearanceResetCapability>,
    pub(crate) data_directory: Option<PathBuf>,
    pub(crate) diagnostics: Option<FailedStartupDiagnostics>,
}
