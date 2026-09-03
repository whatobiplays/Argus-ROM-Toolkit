import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library_composition.dart';
import 'package:argus/features/library/presentation/library_onboarding_page.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/sources/presentation/library_folder_picker.dart';
import 'package:argus/features/sources/presentation/selected_library_folder.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sources/sources_test_fakes.dart';

void main() {
  testWidgets(
    'fresh onboarding completes automatically after the first folder',
    (tester) async {
      final onboarding = FakeLibraryOnboardingApi(freshOnboardingState());
      final privacy = FakeOnboardingSettingsApi();
      final metadata = FakeMetadataSettingsApi();
      final providers = FakeMetadataProvidersApi();
      final sources = FakeSourcesApi();
      sources.onAdd = (_) => AddLocalLibraryRootResult.added(fakeRoot());
      var openedLibrary = 0;
      var openedJobs = 0;

      await tester.pumpWidget(
        _testApp(
          onboarding: onboarding,
          privacy: privacy,
          metadata: metadata,
          providers: providers,
          sources: sources,
          picker: (_, _) async => const SelectedLibraryFolder(
            selection: LocalFilesystemRootSelection('/library/Games'),
            displayName: 'Games',
            safeLocationPresentation: '/library/Games',
          ),
          onOpenLibrary: () => openedLibrary++,
          onOpenJob: (_) => openedJobs++,
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Accept current terms'), findsOneWidget);
      expect(find.text('Open Sources'), findsNothing);
      expect(providers.listCalls, 0);

      await tester.tap(find.text('Accept current terms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use current preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Skip SteamGridDB'), findsOneWidget);

      await tester.tap(find.text('Skip SteamGridDB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a Library folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();

      expect(sources.addCalls, 1);
      expect(onboarding.completeCalls, 1);
      expect(openedLibrary, 1);
      expect(openedJobs, 1);
      expect(find.text('Library setup is complete'), findsOneWidget);
      expect(find.text('Finish & Refresh'), findsNothing);
    },
  );

  testWidgets('existing roots retain an explicit finish action', (
    tester,
  ) async {
    final onboarding = FakeLibraryOnboardingApi(existingRootOnboardingState());
    final privacy = FakeOnboardingSettingsApi(consented: true);
    final metadata = FakeMetadataSettingsApi();
    final providers = FakeMetadataProvidersApi();
    final sources = FakeSourcesApi(roots: [fakeRoot()]);

    await tester.pumpWidget(
      _testApp(
        onboarding: onboarding,
        privacy: privacy,
        metadata: metadata,
        providers: providers,
        sources: sources,
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Add a Library folder'), findsNothing);
    expect(find.text('Finish & Refresh'), findsOneWidget);
    expect(sources.addCalls, 0);

    await tester.ensureVisible(find.text('Finish & Refresh'));
    await tester.tap(find.text('Finish & Refresh'));
    await tester.pumpAndSettle();

    expect(onboarding.completeCalls, 1);
    expect(find.text('Library setup is complete'), findsOneWidget);
  });
}

Widget _testApp({
  required FakeLibraryOnboardingApi onboarding,
  required FakeOnboardingSettingsApi privacy,
  required FakeMetadataSettingsApi metadata,
  required FakeMetadataProvidersApi providers,
  required FakeSourcesApi sources,
  LibraryFolderPicker? picker,
  VoidCallback? onOpenLibrary,
  void Function(JobRunId jobRunId)? onOpenJob,
}) => ProviderScope(
  overrides: [
    libraryOnboardingApiProvider.overrideWithValue(onboarding),
    appearanceSettingsApiProvider.overrideWithValue(privacy),
    libraryMetadataSettingsApiProvider.overrideWithValue(metadata),
    libraryMetadataProvidersApiProvider.overrideWithValue(providers),
    librarySourcesApiProvider.overrideWithValue(sources),
    if (picker != null) libraryFolderPickerProvider.overrideWithValue(picker),
  ],
  child: MaterialApp(
    home: LibraryOnboardingPage(
      onOpenLibrary: onOpenLibrary ?? () {},
      onOpenJob: onOpenJob ?? (_) {},
    ),
  ),
);

LibraryOnboardingState freshOnboardingState() => const LibraryOnboardingState(
  progress: LibraryOnboardingProgress(
    acceptedPrivacyTermsVersion: null,
    acceptedPrivacyAtMs: null,
    metadataPreferencesConfirmed: false,
    providerSetupOutcome: LibraryProviderSetupOutcome.pending,
    completedAtMs: null,
  ),
  requiredPrivacyTermsVersion: 'phase-003-v1',
  requiresPrivacyAcceptance: true,
  requiresRootSelection: true,
  credentialConfigured: false,
  complete: false,
);

LibraryOnboardingState existingRootOnboardingState() =>
    const LibraryOnboardingState(
      progress: LibraryOnboardingProgress(
        acceptedPrivacyTermsVersion: 'phase-003-v1',
        acceptedPrivacyAtMs: 1,
        metadataPreferencesConfirmed: true,
        providerSetupOutcome: LibraryProviderSetupOutcome.skipped,
        completedAtMs: null,
      ),
      requiredPrivacyTermsVersion: 'phase-003-v1',
      requiresPrivacyAcceptance: false,
      requiresRootSelection: false,
      credentialConfigured: false,
      complete: false,
    );

final class FakeLibraryOnboardingApi implements LibraryOnboardingApi {
  FakeLibraryOnboardingApi(this.state);

  LibraryOnboardingState state;
  int completeCalls = 0;

  @override
  Future<LibraryOnboardingState> getState() => Future.value(state);

  @override
  Future<LibraryOnboardingState> confirmMetadataPreferences(
    MetadataSettings settings,
  ) {
    state = state.copyWith(
      progress: state.progress.copyWith(metadataPreferencesConfirmed: true),
    );
    return Future.value(state);
  }

  @override
  Future<LibraryOnboardingState> recordProviderSetup(
    LibraryProviderSetupDecision decision,
  ) {
    state = state.copyWith(
      progress: state.progress.copyWith(
        providerSetupOutcome: switch (decision) {
          LibraryProviderSetupDecision.configured =>
            LibraryProviderSetupOutcome.configured,
          LibraryProviderSetupDecision.skipped =>
            LibraryProviderSetupOutcome.skipped,
        },
      ),
    );
    return Future.value(state);
  }

  @override
  Future<CompleteLibraryOnboardingAndRefreshResult> completeAndRefresh() {
    completeCalls++;
    state = state.copyWith(
      progress: state.progress.copyWith(completedAtMs: 1),
      complete: true,
    );
    return Future.value(
      CompleteLibraryOnboardingAndRefreshResult.admitted(
        state: state,
        handle: const OperationHandle(
          jobRunId: JobRunId('11111111111111111111111111111111'),
          operationType: 'library_refresh',
        ),
      ),
    );
  }

  @override
  Future<AddLibraryRootAndRefreshResult> addLibraryRootAndRefresh(
    LocalFilesystemRootSelection selection,
  ) => throw UnsupportedError('The page uses the root-only add seam');
}

final class FakeOnboardingSettingsApi implements SettingsApi {
  FakeOnboardingSettingsApi({this.consented = false});

  bool consented;

  @override
  Future<AppearanceSettings> getAppearanceSettings() =>
      Future.value(const AppearanceSettings(themeMode: ThemeMode.system));

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) =>
      Future.value();

  @override
  Future<PrivacyConsent> getPrivacyConsent() => Future.value(_consent());

  @override
  Future<PrivacyConsent> acceptPrivacyTerms(PrivacyTermsVersion termsVersion) {
    consented = true;
    return Future.value(_consent());
  }

  PrivacyConsent _consent() => PrivacyConsent(
    acceptedTermsVersion: consented
        ? const PrivacyTermsVersion('phase-003-v1')
        : null,
    acceptedAtMs: consented ? 1 : null,
    requiredTermsVersion: const PrivacyTermsVersion('phase-003-v1'),
    satisfiesCurrentRequiredTerms: consented,
  );
}

final class FakeMetadataSettingsApi implements MetadataSettingsApi {
  @override
  Future<MetadataSettings> getMetadataSettings() => Future.value(
    const MetadataSettings(preferredRegions: [], preferredLanguages: []),
  );

  @override
  Future<MetadataProviderSettings> getMetadataProviderSettings() =>
      Future.value(const MetadataProviderSettings(enabledProviders: []));

  @override
  Future<MetadataSettingsUpdateResult> updateMetadataSettings(
    MetadataSettings settings,
  ) => Future.value(
    MetadataSettingsUpdateResult.committedNoResolutionWork(settings),
  );

  @override
  Future<MetadataProviderSettingsUpdateResult> updateMetadataProviderSettings(
    MetadataProviderSettings settings,
  ) => Future.value(
    MetadataProviderSettingsUpdateResult.committedNoResolutionWork(settings),
  );
}

final class FakeMetadataProvidersApi implements MetadataProvidersApi {
  int listCalls = 0;

  @override
  Future<List<MetadataProviderReadiness>> listMetadataProviderReadiness() {
    listCalls++;
    return Future.value(const [
      MetadataProviderReadiness(
        providerId: 'playmatch',
        enabled: true,
        capabilityReadiness: [
          ProviderCapabilityReadiness(
            capability: ProviderCapability.contentMatching,
            state: ProviderReadinessState.ready,
          ),
        ],
        credentialConfigured: false,
      ),
      MetadataProviderReadiness(
        providerId: 'gametdb',
        enabled: true,
        capabilityReadiness: [
          ProviderCapabilityReadiness(
            capability: ProviderCapability.metadataRefresh,
            state: ProviderReadinessState.ready,
          ),
        ],
        credentialConfigured: false,
      ),
      MetadataProviderReadiness(
        providerId: 'steamgriddb',
        enabled: true,
        capabilityReadiness: [
          ProviderCapabilityReadiness(
            capability: ProviderCapability.artworkDiscovery,
            state: ProviderReadinessState.missingCredentials,
          ),
        ],
        credentialConfigured: false,
      ),
    ]);
  }

  @override
  Future<ProviderCredentialReadiness> setMetadataProviderCredential({
    required String providerId,
    required List<int> credentialInput,
  }) => Future.value(
    ProviderCredentialReadiness(
      providerId: providerId,
      state: ProviderReadinessState.ready,
      credentialConfigured: true,
    ),
  );

  @override
  Future<ProviderCredentialReadiness> removeMetadataProviderCredential(
    String providerId,
  ) => Future.value(
    ProviderCredentialReadiness(
      providerId: providerId,
      state: ProviderReadinessState.missingCredentials,
      credentialConfigured: false,
    ),
  );
}
