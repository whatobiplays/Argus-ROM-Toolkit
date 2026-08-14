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

/// Test-owned holder for the injected appearance reconciliation demand source.
///
/// Tests emit demands synchronously and control stream lifetime explicitly.
final class AppearanceReconciliationDemandHost
    extends Notifier<AppearanceReconciliationDemandSource> {
  StreamController<AppearanceReconciliationDemand> _controller =
      StreamController<AppearanceReconciliationDemand>.broadcast();
  StreamController<AppearanceReconciliationDemand>? _retiredController;

  @override
  AppearanceReconciliationDemandSource build() =>
      AppearanceReconciliationDemandSource(_controller.stream);

  /// Publishes one refresh demand without any timing dependency.
  void requestRefresh() =>
      _controller.add(const AppearanceReconciliationDemandRefresh());

  /// Replaces the exposed source, retiring the previous controller so stale
  /// signals can be proven inert.
  void replaceSource() {
    _retiredController = _controller;
    _controller = StreamController<AppearanceReconciliationDemand>.broadcast();
    state = AppearanceReconciliationDemandSource(_controller.stream);
  }

  /// Emits a demand on the retired source for stale-signal suppression tests.
  void emitOnRetiredSource() {
    _retiredController?.add(const AppearanceReconciliationDemandRefresh());
  }

  /// Closes the demand stream for deterministic teardown.
  Future<void> close() async {
    await _controller.close();
    await _retiredController?.close();
  }
}

/// Provider exposing [AppearanceReconciliationDemandHost] to overrides.
final appearanceReconciliationDemandHostProvider =
    NotifierProvider<
      AppearanceReconciliationDemandHost,
      AppearanceReconciliationDemandSource
    >(AppearanceReconciliationDemandHost.new);
