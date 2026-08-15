import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_event_coordinator.dart';
import 'jobs_event_coordinator.dart';
import 'sources_event_coordinator.dart';

/// Owns the single application-level Riverpod scope.
class ArgusBootstrap extends StatelessWidget {
  /// Creates the application bootstrap root.
  const ArgusBootstrap({this.clientGatewayFactory, super.key});

  /// Optional narrow test seam for pointing the real composition at a
  /// test-owned bridge gateway (for example an isolated data directory).
  ///
  /// Production startup uses [bootstrapArgus] with no override; this seam
  /// deliberately exposes only the gateway factory, never an arbitrary
  /// provider-override list or environment-driven behavior.
  final ArgusClientGateway Function()? clientGatewayFactory;

  @override
  Widget build(BuildContext context) {
    final factory = clientGatewayFactory;
    return ProviderScope(
      overrides: [
        if (factory != null)
          argusClientGatewayFactoryProvider.overrideWithValue(factory),
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
        sourcesApiProvider.overrideWith(
          (ref) => ref.watch(argusClientProvider).sources,
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
          (ref) => ref.watch(sourcesEventCoordinatorProvider),
        ),
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
      child: const ArgusApp(),
    );
  }
}

/// Starts the application with its root dependency scope.
void bootstrapArgus() {
  runApp(const ArgusBootstrap());
}
