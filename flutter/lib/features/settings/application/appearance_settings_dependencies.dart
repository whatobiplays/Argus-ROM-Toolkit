import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'appearance_settings_state.dart';

part 'appearance_settings_dependencies.g.dart';

/// Focused appearance-settings capability injected by app composition.
///
/// This is a dependency-injection seam only: it contains no root-client
/// construction, retries, caching, or workflow.
@Riverpod(keepAlive: true)
SettingsApi appearanceSettingsApi(Ref ref) {
  throw StateError(
    'appearanceSettingsApiProvider must be supplied by app composition',
  );
}

/// Runtime generation context injected by app composition.
///
/// The default is pre-ready; app composition supplies the current runtime
/// identity derived from backend readiness.
@Riverpod(keepAlive: true)
AppearanceRuntimeContext appearanceRuntimeContext(Ref ref) =>
    const AppearanceRuntimeContext.preReady();
