import 'dart:async';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_event_coordinator.dart';
import 'foreground_execution_coordinator.dart';
import 'jobs_event_coordinator.dart';
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
        platformHostApiProvider.overrideWithValue(platform.api),
        localFilesystemPlatformApiProvider.overrideWithValue(
          platform.localFilesystemApi,
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
          (ref) => ref.watch(jobsEventCoordinatorProvider),
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

/// Combines runtime-event invalidations with platform storage transitions.
/// Only the Sources channel receives the platform transition; Jobs retains
/// its existing event and recovery authorities.
SourcesReconciliationDemandSource _composeSourcesReconciliationDemands(
  Ref ref,
  SourcesReconciliationDemandSource eventDemands,
  PlatformStorageReconciliationDemandSource storageDemands,
) {
  final merged = StreamController<SourcesReconciliationDemand>.broadcast();
  final eventSubscription = eventDemands.stream.listen(merged.add);
  final storageSubscription = storageDemands.stream.listen((_) {
    merged.add(const SourcesReconciliationDemand.rootsChanged());
  });
  ref.onDispose(() {
    unawaited(eventSubscription.cancel());
    unawaited(storageSubscription.cancel());
    unawaited(merged.close());
  });
  return SourcesReconciliationDemandSource(merged.stream);
}
