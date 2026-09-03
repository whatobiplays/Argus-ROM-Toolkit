import 'dart:async';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_event_coordinator.dart';
import 'application_lifecycle_coordinator.dart';
import 'foreground_execution_coordinator.dart';
import 'jobs_event_coordinator.dart';
import 'library_event_coordinator.dart';
import 'sources_event_coordinator.dart';

/// Owns the single application-level Riverpod scope.
class ArgusBootstrap extends StatelessWidget {
  /// Creates the application bootstrap root.
  const ArgusBootstrap({
    this.clientGatewayFactory,
    this.libraryFolderPicker,
    this.platformHostComposition,
    super.key,
  });

  /// Optional narrow test seam for pointing the real composition at a
  /// test-owned bridge gateway (for example an isolated data directory).
  ///
  /// Production startup uses [bootstrapArgus] with no override; this seam
  /// deliberately exposes only the gateway factory, never an arbitrary
  /// provider-override list or environment-driven behavior.
  final ArgusClientGateway Function()? clientGatewayFactory;

  /// Optional narrow test seam for the existing [LibraryFolderPicker]
  /// contract, applied inside this scope exactly like the gateway seam.
  ///
  /// Production startup uses [bootstrapArgus] with no override; this seam
  /// deliberately exposes only the picker contract, never an arbitrary
  /// provider-override list or environment-driven behavior.
  final LibraryFolderPicker? libraryFolderPicker;

  /// Optional narrow test seam for the complete platform-host composition.
  ///
  /// Production startup uses [createPlatformHostComposition]; tests may
  /// supply a fake [PlatformHostApi] and readiness-gate flag. This seam
  /// deliberately exposes the composition object, never an arbitrary
  /// provider-override list or raw MethodChannel hook.
  final PlatformHostComposition? platformHostComposition;

  @override
  Widget build(BuildContext context) {
    final factory = clientGatewayFactory;
    final picker = libraryFolderPicker;
    final platform = platformHostComposition ?? createPlatformHostComposition();
    return ProviderScope(
      overrides: [
        platformReadinessRequiredProvider.overrideWithValue(
          platform.requiresReadinessGate,
        ),
        platformHostApiProvider.overrideWithValue(platform.api),
        localFilesystemPlatformApiProvider.overrideWithValue(
          platform.localFilesystemApi,
        ),
        macosLibraryFolderPickerApiProvider.overrideWithValue(
          platform.macosLibraryFolderPickerApi,
        ),
        diagnosticsPublicationApiProvider.overrideWithValue(
          platform.diagnosticsPublicationApi,
        ),
        platformMountedVolumesReaderProvider.overrideWithValue(
          platform.localFilesystemApi?.readMountedVolumes,
        ),
        foregroundExecutionHostApiProvider.overrideWithValue(
          platform.foregroundExecutionHostApi,
        ),
        sourcesPresentationCapabilitiesProvider.overrideWithValue(
          platform.requiresReadinessGate
              ? const SourcesPresentationCapabilities(
                  singleRootScanExecution: true,
                  scanAllExecution: true,
                  activeRootCancelAndRemove: true,
                  localFilesystemBrowser: true,
                )
              : const SourcesPresentationCapabilities(),
        ),
        if (factory != null)
          argusClientGatewayFactoryProvider.overrideWithValue(factory)
        else if (platform.requiresReadinessGate)
          standardApplicationDataDirectoryProvider.overrideWith((ref) {
            final configuration = ref
                .read(platformReadinessControllerProvider.notifier)
                .runtimeConfiguration;
            if (configuration == null) {
              throw StateError(
                'Android runtime configuration requested before platform '
                'readiness',
              );
            }
            return configuration.standardApplicationDataDirectory;
          }),
        if (picker != null)
          libraryFolderPickerProvider.overrideWithValue(picker),
        if (platform.requiresReadinessGate)
          startupPresentationCapabilitiesProvider.overrideWithValue(
            const StartupPresentationCapabilities(
              diagnosticsExport: true,
              diagnosticsSharing: true,
              openDataDirectory: false,
            ),
          ),
        appearanceSettingsApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).settings,
        ),
        appearanceRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const AppearanceRuntimeContext.preReady()
              : AppearanceRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        appearanceReconciliationDemandProvider.overrideWith(
          (ref) => ref.watch(appearanceEventCoordinatorProvider),
        ),
        settingsMetadataApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).metadataSettings,
        ),
        settingsMetadataProvidersApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).metadataProviders,
        ),
        libraryApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).library,
        ),
        librarySourcesApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).sources,
        ),
        libraryOnboardingApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).onboarding,
        ),
        libraryMetadataSettingsApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).metadataSettings,
        ),
        libraryMetadataProvidersApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).metadataProviders,
        ),
        if (platform.foregroundExecutionHostApi != null)
          libraryRefreshApiProvider.overrideWith(
            (ref) =>
                ref.watch(foregroundExecutionCoordinatorProvider).refreshApi,
          )
        else
          libraryRefreshApiProvider.overrideWith(
            (ref) => ref.watch(argusClientProvider).refresh,
          ),
        libraryGamesApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).games,
        ),
        libraryArtworkApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).artwork,
        ),
        libraryRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const LibraryRuntimeContext.preReady()
              : LibraryRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        libraryReconciliationDemandProvider.overrideWith(
          (ref) => _composeLibraryReconciliationDemands(
            ref,
            ref.watch(libraryEventCoordinatorProvider),
            ref.watch(applicationLifecycleReconciliationDemandProvider),
          ),
        ),
        if (platform.foregroundExecutionHostApi != null)
          sourcesApiProvider.overrideWith(
            (ref) =>
                ref.watch(foregroundExecutionCoordinatorProvider).sourcesApi,
          )
        else
          sourcesApiProvider.overrideWith(
            (ref) => ref.watch(argusClientProvider).sources,
          ),
        if (platform.foregroundExecutionHostApi != null)
          sourcesJobsApiProvider.overrideWith(
            (ref) => ref.watch(foregroundExecutionCoordinatorProvider).jobsApi,
          )
        else
          sourcesJobsApiProvider.overrideWith(
            (ref) => ref.watch(argusClientProvider).jobs,
          ),
        sourcesRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const SourcesRuntimeContext.preReady()
              : SourcesRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        sourcesReconciliationDemandProvider.overrideWith(
          (ref) => _composeSourcesReconciliationDemands(
            ref,
            ref.watch(sourcesEventCoordinatorProvider),
            ref.watch(platformStorageReconciliationDemandProvider),
            ref.watch(applicationLifecycleReconciliationDemandProvider),
          ),
        ),
        if (platform.foregroundExecutionHostApi != null)
          jobsApiProvider.overrideWith(
            (ref) => ref.watch(foregroundExecutionCoordinatorProvider).jobsApi,
          )
        else
          jobsApiProvider.overrideWith(
            (ref) => ref.watch(argusClientProvider).jobs,
          ),
        jobsRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const JobsRuntimeContext.preReady()
              : JobsRuntimeContext.ready(runtimeInstanceId: runtimeInstanceId);
        }),
        jobsReconciliationDemandProvider.overrideWith(
          (ref) => _composeJobsReconciliationDemands(
            ref,
            ref.watch(jobsEventCoordinatorProvider),
            ref.watch(applicationLifecycleReconciliationDemandProvider),
          ),
        ),
      ],
      child: ArgusApp(
        platformReadinessRequired: platform.requiresReadinessGate,
      ),
    );
  }
}

/// Starts the application with its root dependency scope.
void bootstrapArgus() {
  runApp(const ArgusBootstrap());
}

/// Combines runtime-event invalidations with platform storage and app-lifecycle
/// transitions while preserving each feature's existing provider seam.
SourcesReconciliationDemandSource _composeSourcesReconciliationDemands(
  Ref ref,
  SourcesReconciliationDemandSource eventDemands,
  PlatformStorageReconciliationDemandSource storageDemands,
  ApplicationLifecycleReconciliationDemandSource lifecycleDemands,
) {
  final merged = StreamController<SourcesReconciliationDemand>.broadcast();
  var storageDemandPending = false;
  var lifecycleDemandPending = false;
  var flushScheduled = false;

  void flushPlatformDemands() {
    if (merged.isClosed) return;
    flushScheduled = false;
    final shouldRefreshRoots = storageDemandPending;
    final shouldReconcileLoadedScopes = lifecycleDemandPending;
    storageDemandPending = false;
    lifecycleDemandPending = false;

    // A lifecycle demand already refreshes the authoritative root list and
    // every loaded hierarchy/browser scope. It therefore subsumes a storage
    // demand emitted by the same Android resume without losing the loaded
    // scope reconciliation.
    if (shouldReconcileLoadedScopes) {
      merged.add(const SourcesReconciliationDemand.lifecycleChanged());
    } else if (shouldRefreshRoots) {
      merged.add(const SourcesReconciliationDemand.rootsChanged());
    }
  }

  void schedulePlatformDemand({
    required bool storage,
    required bool lifecycle,
  }) {
    storageDemandPending = storageDemandPending || storage;
    lifecycleDemandPending = lifecycleDemandPending || lifecycle;
    if (flushScheduled) return;
    flushScheduled = true;
    scheduleMicrotask(flushPlatformDemands);
  }

  final eventSubscription = eventDemands.stream.listen(merged.add);
  final storageSubscription = storageDemands.stream.listen((_) {
    schedulePlatformDemand(storage: true, lifecycle: false);
  });
  final lifecycleSubscription = lifecycleDemands.stream.listen((_) {
    schedulePlatformDemand(storage: false, lifecycle: true);
  });
  ref.onDispose(() {
    unawaited(eventSubscription.cancel());
    unawaited(storageSubscription.cancel());
    unawaited(lifecycleSubscription.cancel());
    unawaited(merged.close());
  });
  return SourcesReconciliationDemandSource(merged.stream);
}

/// Combines runtime-event and app-lifecycle invalidations for Library.
LibraryReconciliationDemandSource _composeLibraryReconciliationDemands(
  Ref ref,
  LibraryReconciliationDemandSource eventDemands,
  ApplicationLifecycleReconciliationDemandSource lifecycleDemands,
) {
  final merged = StreamController<LibraryReconciliationDemand>.broadcast();
  final eventSubscription = eventDemands.stream.listen(merged.add);
  final lifecycleSubscription = lifecycleDemands.stream.listen((_) {
    merged.add(const LibraryReconciliationDemand.listChanged());
  });
  ref.onDispose(() {
    unawaited(eventSubscription.cancel());
    unawaited(lifecycleSubscription.cancel());
    unawaited(merged.close());
  });
  return LibraryReconciliationDemandSource(merged.stream);
}

/// Combines runtime-event and app-lifecycle invalidations for Jobs.
JobsReconciliationDemandSource _composeJobsReconciliationDemands(
  Ref ref,
  JobsReconciliationDemandSource eventDemands,
  ApplicationLifecycleReconciliationDemandSource lifecycleDemands,
) {
  final merged = StreamController<JobsReconciliationDemand>.broadcast();
  final eventSubscription = eventDemands.stream.listen(merged.add);
  final lifecycleSubscription = lifecycleDemands.stream.listen((_) {
    merged.add(const JobsReconciliationDemand.listChanged());
  });
  ref.onDispose(() {
    unawaited(eventSubscription.cancel());
    unawaited(lifecycleSubscription.cancel());
    unawaited(merged.close());
  });
  return JobsReconciliationDemandSource(merged.stream);
}
