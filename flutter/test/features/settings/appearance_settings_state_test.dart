import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppearanceSettingsState.ready exposes confirmed, presented, save, and '
      'synchronization semantics', () {
    const confirmed = AppearanceSettings(themeMode: ThemeMode.light);
    const presented = AppearanceSettings(themeMode: ThemeMode.dark);
    const state = AppearanceSettingsState.ready(
      confirmed: confirmed,
      presented: presented,
      saveOperation: AppearanceSaveOperation.saving(requested: presented),
      synchronization: AppearanceSynchronization.synchronized(),
    );

    expect(state, isA<AppearanceSettingsStateReady>());
    expect(state.confirmed, confirmed);
    expect(state.presented, presented);
    expect(
      state.saveOperation,
      const AppearanceSaveOperation.saving(requested: presented),
    );
    expect(
      state.synchronization,
      const AppearanceSynchronization.synchronized(),
    );
  });

  test('AppearanceRuntimeContext.ready carries the runtime instance id', () {
    const context = AppearanceRuntimeContext.ready(
      runtimeInstanceId: RuntimeInstanceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    );

    expect(context, isA<AppearanceRuntimeContextReady>());
    final runtimeInstanceId = switch (context) {
      AppearanceRuntimeContextReady(:final runtimeInstanceId) =>
        runtimeInstanceId,
      AppearanceRuntimeContextPreReady() => null,
    };
    expect(
      runtimeInstanceId,
      const RuntimeInstanceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    );
  });

  test(
    'appearance dependency seams default to preReady and an explicit throw',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(appearanceRuntimeContextProvider),
        const AppearanceRuntimeContext.preReady(),
      );
      expect(
        () => container.read(appearanceSettingsApiProvider),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'must be supplied by app composition',
            ),
          ),
        ),
      );
    },
  );
}
