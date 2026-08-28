/// Narrow public app-composition barrel for platform hosting.
library;

export 'application/platform_host_api.dart'
    show
        NotificationAuthorization,
        PlatformHostApi,
        PlatformHostException,
        PlatformHostSnapshot,
        PlatformReadinessFailureKind;
export 'application/foreground_execution_host_api.dart'
    show
        ForegroundExecutionCancelRequested,
        ForegroundExecutionHostApi,
        ForegroundExecutionHostEvent,
        ForegroundExecutionHostLost,
        ForegroundExecutionLease,
        ForegroundExecutionProjection,
        ForegroundExecutionTimedOut,
        maxForegroundExecutionActiveJobs;
export 'application/foreground_execution_host_composition.dart'
    show foregroundExecutionHostApiProvider;
export 'application/local_filesystem_platform_api.dart'
    show
        LocalFilesystemPlatformApi,
        LocalFilesystemPlatformException,
        LocalFilesystemPlatformFailureKind,
        PlatformMountedVolume,
        maxPlatformMountedVolumes;
export 'application/diagnostics_publication_api.dart'
    show
        DiagnosticsPublicationApi,
        DiagnosticsPublicationException,
        DiagnosticsPublicationFailureKind;
export 'application/platform_readiness_controller.dart'
    show
        PlatformMountedVolumesReader,
        PlatformReadinessController,
        PlatformStorageReconciliationDemand,
        PlatformStorageReconciliationDemandSource,
        PlatformStorageReconciliationReason,
        platformHostApiProvider,
        platformMountedVolumesReaderProvider,
        platformReadinessRequiredProvider,
        platformReadinessControllerProvider,
        platformStorageReconciliationDemandProvider;
export 'application/platform_readiness_state.dart'
    show
        PlatformReadinessLoading,
        PlatformReadinessReady,
        PlatformReadinessRequiresAllFilesAccess,
        PlatformReadinessRequiresNotificationPermission,
        PlatformReadinessState,
        PlatformReadinessUnavailable,
        PlatformRuntimeConfiguration,
        classifyPlatformReadiness;
export 'native/platform_host_factory.dart'
    show PlatformHostComposition, createPlatformHostComposition;
export 'presentation/platform_readiness_gate.dart' show PlatformReadinessGate;
