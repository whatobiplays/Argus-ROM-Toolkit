/// Narrow app-composition entry point for the Settings feature.
///
/// Feature-internal application and presentation details stay private;
/// app composition consumes only these contracts.
library;

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
