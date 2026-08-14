import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_event_coordinator.dart';

/// Owns the single application-level Riverpod scope.
class ArgusBootstrap extends StatelessWidget {
  /// Creates the application bootstrap root.
  const ArgusBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
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
      ],
      child: const ArgusApp(),
    );
  }
}

/// Starts the application with its root dependency scope.
void bootstrapArgus() {
  runApp(const ArgusBootstrap());
}
