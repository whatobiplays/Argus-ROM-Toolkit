/// Narrow app-composition entry point for the Settings feature.
///
/// Feature-internal application and presentation details stay private;
/// app composition consumes only these contracts.
library;

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'application/appearance_settings_controller.dart'
    show AppearanceSettingsController, appearanceSettingsControllerProvider;
export 'application/appearance_settings_dependencies.dart'
    show
        appearanceReconciliationDemandProvider,
        appearanceRuntimeContextProvider,
        appearanceSettingsApiProvider;
export 'application/appearance_settings_state.dart'
    show
        AppearanceReconciliationDemand,
        AppearanceReconciliationDemandRefresh,
        AppearanceReconciliationDemandSource,
        AppearanceRuntimeContext,
        AppearanceRuntimeContextPreReady,
        AppearanceRuntimeContextReady,
        AppearanceSettingsState,
        AppearanceSettingsStateReady;
export 'presentation/appearance_initialization_view.dart'
    show AppearanceInitializationFailureView, AppearanceInitializationView;

part 'settings_composition.g.dart';

/// Optional Phase-003 metadata settings capability supplied by app
/// composition. Legacy and isolated test embeddings leave it unavailable.
@Riverpod(keepAlive: true)
MetadataSettingsApi? settingsMetadataApi(Ref ref) => null;

/// Optional Phase-003 provider readiness and write-only credential capability.
@Riverpod(keepAlive: true)
MetadataProvidersApi? settingsMetadataProvidersApi(Ref ref) => null;
