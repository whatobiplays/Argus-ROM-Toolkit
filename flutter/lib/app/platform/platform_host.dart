/// Narrow public app-composition barrel for platform hosting.
library;

export 'application/platform_host_api.dart'
    show
        NotificationAuthorization,
        PlatformHostApi,
        PlatformHostException,
        PlatformHostSnapshot,
        PlatformReadinessFailureKind;
export 'application/local_filesystem_platform_api.dart'
    show
        LocalFilesystemPlatformApi,
        LocalFilesystemPlatformException,
        LocalFilesystemPlatformFailureKind,
        PlatformMountedVolume,
        maxPlatformMountedVolumes;
export 'application/platform_readiness_controller.dart'
    show
        PlatformReadinessController,
        platformHostApiProvider,
        platformReadinessControllerProvider;
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
