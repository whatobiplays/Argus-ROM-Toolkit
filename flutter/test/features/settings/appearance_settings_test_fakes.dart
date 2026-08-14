import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds a valid 32-character lowercase-hex [RuntimeInstanceId] from one
/// fill character.
RuntimeInstanceId appearanceTestId(String fill) => RuntimeInstanceId(fill * 32);

/// Deterministic [SettingsApi] fake.
///
/// Every read returns a fresh pending [Completer] and every update records
/// the submitted aggregate with its own pending completer, so tests control
/// each operation's outcome explicitly without timing.
final class FakeSettingsApi implements SettingsApi {
  final List<Completer<AppearanceSettings>> readRequests =
      <Completer<AppearanceSettings>>[];
  final List<({AppearanceSettings settings, Completer<void> completer})>
  updateRequests =
      <({AppearanceSettings settings, Completer<void> completer})>[];

  @override
  Future<AppearanceSettings> getAppearanceSettings() {
    final completer = Completer<AppearanceSettings>();
    readRequests.add(completer);
    return completer.future;
  }

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) {
    final completer = Completer<void>();
    updateRequests.add((settings: settings, completer: completer));
    return completer.future;
  }
}

/// Test-owned holder for the injected [AppearanceRuntimeContext].
///
/// Tests override [appearanceRuntimeContextProvider] with this provider and
/// transition runtime generations synchronously.
final class AppearanceRuntimeContextHost
    extends Notifier<AppearanceRuntimeContext> {
  @override
  AppearanceRuntimeContext build() => const AppearanceRuntimeContext.preReady();

  /// Publishes a new runtime context synchronously.
  void setContext(AppearanceRuntimeContext context) => state = context;
}

/// Provider exposing [AppearanceRuntimeContextHost] to provider overrides.
final appearanceRuntimeContextHostProvider =
    NotifierProvider<AppearanceRuntimeContextHost, AppearanceRuntimeContext>(
      AppearanceRuntimeContextHost.new,
    );
