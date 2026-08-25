import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_composition.dart';
import '../../startup/startup.dart';
import '../../sources/presentation/library_folder_picker.dart';
import '../../sources/presentation/selected_library_folder.dart';
import '../library_composition.dart';

/// Query-authoritative Library onboarding. Durable progress comes from the
/// backend; transient credential input exists only inside the provider step.
class LibraryOnboardingPage extends ConsumerStatefulWidget {
  const LibraryOnboardingPage({
    required this.onOpenLibrary,
    required this.onOpenSources,
    required this.onOpenJob,
    super.key,
  });

  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSources;
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  ConsumerState<LibraryOnboardingPage> createState() =>
      _LibraryOnboardingPageState();
}

class _LibraryOnboardingPageState extends ConsumerState<LibraryOnboardingPage> {
  late Future<_OnboardingSnapshot> _future;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OnboardingSnapshot> _load() async {
    final onboarding = ref.read(libraryOnboardingApiProvider);
    final providers = ref.read(libraryMetadataProvidersApiProvider);
    final metadata = ref.read(libraryMetadataSettingsApiProvider);
    final privacy = await ref
        .read(appearanceSettingsApiProvider)
        .getPrivacyConsent();
    final state = await onboarding.getState();
    final settings = await metadata.getMetadataSettings();
    final readiness =
        privacy.satisfiesCurrentRequiredTerms &&
            state.progress.metadataPreferencesConfirmed
        ? await providers.listMetadataProviderReadiness()
        : const <MetadataProviderReadiness>[];
    return _OnboardingSnapshot(
      state: state,
      privacyConsent: privacy,
      readiness: readiness,
      metadata: settings,
    );
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await operation();
      await _reload();
    } on ClientFailure {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That onboarding step could not be saved'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<ProviderCredentialReadiness> _setCredential(List<int> secret) async {
    if (_submitting) {
      throw const TransportFailure('Another onboarding action is in progress');
    }
    setState(() => _submitting = true);
    try {
      return await ref
          .read(libraryMetadataProvidersApiProvider)
          .setSteamgriddbCredential(secret);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addRoot() async {
    final picker = ref.read(libraryFolderPickerProvider);
    final SelectedLibraryFolder? selected;
    try {
      selected = await picker(context, ref);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Library root picker could not open')),
      );
      return;
    }
    if (selected == null || !mounted) return;
    final chosen = selected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Library root?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(chosen.displayName),
            const SizedBox(height: 4),
            Text(chosen.safeLocationPresentation),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add folder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(librarySourcesApiProvider)
          .addLocalLibraryRoot(chosen.selection);
      if (!mounted) return;
      switch (result) {
        case AddLocalLibraryRootResultAdded():
        case AddLocalLibraryRootResultAlreadyConfigured():
          await _completeFreshOnboarding();
        case AddLocalLibraryRootResultOverlapsExisting():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That folder overlaps an existing root'),
            ),
          );
          setState(() {
            _future = _load();
          });
      }
    } on ClientFailure {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Library root could not be added')),
      );
      setState(() {
        _future = _load();
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _completeFreshOnboarding() async {
    try {
      final result = await ref
          .read(libraryOnboardingApiProvider)
          .completeAndRefresh();
      if (!mounted) return;
      switch (result) {
        case CompleteLibraryOnboardingAndRefreshResultAdmitted(:final handle):
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Library setup complete; refresh started'),
            ),
          );
          widget.onOpenJob(handle.jobRunId);
          widget.onOpenLibrary();
        case CompleteLibraryOnboardingAndRefreshResultNotAdmitted(:final error):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Library setup saved, but refresh could not start: ${error.code.value}',
              ),
            ),
          );
          widget.onOpenLibrary();
      }
      setState(() {
        _future = _load();
      });
    } on ClientFailure {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Library setup was saved but could not be completed'),
        ),
      );
      setState(() {
        _future = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<_OnboardingSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    _future = _load();
                  });
                },
                child: const Text('Retry Library setup'),
              ),
            );
          }
          final data = snapshot.data!;
          return _OnboardingContent(
            snapshot: data,
            submitting: _submitting,
            onAcceptPrivacy: () => _run(
              () => ref
                  .read(appearanceSettingsApiProvider)
                  .acceptPrivacyTerms(data.privacyConsent.requiredTermsVersion)
                  .then<void>((_) {}),
            ),
            onDeclinePrivacy: () => ref.read(appTerminatorProvider)(),
            onConfirmMetadata: () => _run(
              () => ref
                  .read(libraryOnboardingApiProvider)
                  .confirmMetadataPreferences(
                    _metadataForConfirmation(
                      data.metadata,
                      Localizations.localeOf(context),
                    ),
                  )
                  .then<void>((_) {}),
            ),
            onSetCredential: _setCredential,
            onRecordConfigured: () => _run(
              () => ref
                  .read(libraryOnboardingApiProvider)
                  .recordProviderSetup(LibraryProviderSetupDecision.configured)
                  .then<void>((_) {}),
            ),
            onRemoveCredential: () => _run(
              () => ref
                  .read(libraryMetadataProvidersApiProvider)
                  .removeSteamgriddbCredential()
                  .then<void>((_) {}),
            ),
            onSkipProvider: () => _run(
              () => ref
                  .read(libraryOnboardingApiProvider)
                  .recordProviderSetup(LibraryProviderSetupDecision.skipped)
                  .then<void>((_) {}),
            ),
            onAddRoot: _addRoot,
            onComplete: () => _run(() async {
              final messenger = ScaffoldMessenger.of(context);
              final result = await ref
                  .read(libraryOnboardingApiProvider)
                  .completeAndRefresh();
              if (!mounted) return;
              switch (result) {
                case CompleteLibraryOnboardingAndRefreshResultAdmitted(
                  :final handle,
                ):
                  widget.onOpenJob(handle.jobRunId);
                  widget.onOpenLibrary();
                case CompleteLibraryOnboardingAndRefreshResultNotAdmitted(
                  :final error,
                ):
                  messenger.showSnackBar(
                    SnackBar(content: Text('Setup saved: ${error.code.value}')),
                  );
                  widget.onOpenLibrary();
              }
            }),
            onOpenLibrary: widget.onOpenLibrary,
            onOpenSources: widget.onOpenSources,
          );
        },
      ),
    ),
  );
}

final class _OnboardingSnapshot {
  const _OnboardingSnapshot({
    required this.state,
    required this.privacyConsent,
    required this.readiness,
    required this.metadata,
  });

  final LibraryOnboardingState state;
  final PrivacyConsent privacyConsent;
  final List<MetadataProviderReadiness> readiness;
  final MetadataSettings metadata;
}

class _OnboardingContent extends StatelessWidget {
  const _OnboardingContent({
    required this.snapshot,
    required this.submitting,
    required this.onAcceptPrivacy,
    required this.onDeclinePrivacy,
    required this.onConfirmMetadata,
    required this.onSetCredential,
    required this.onRecordConfigured,
    required this.onRemoveCredential,
    required this.onSkipProvider,
    required this.onAddRoot,
    required this.onComplete,
    required this.onOpenLibrary,
    required this.onOpenSources,
  });

  final _OnboardingSnapshot snapshot;
  final bool submitting;
  final VoidCallback onAcceptPrivacy;
  final VoidCallback onDeclinePrivacy;
  final VoidCallback onConfirmMetadata;
  final Future<ProviderCredentialReadiness> Function(List<int>) onSetCredential;
  final Future<void> Function() onRecordConfigured;
  final Future<void> Function() onRemoveCredential;
  final VoidCallback onSkipProvider;
  final VoidCallback onAddRoot;
  final VoidCallback onComplete;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    final state = snapshot.state;
    if (state.complete) {
      return _OnboardingComplete(onOpenLibrary: onOpenLibrary);
    }
    final progress = state.progress;
    final privacyComplete =
        snapshot.privacyConsent.satisfiesCurrentRequiredTerms;
    final metadataComplete = progress.metadataPreferencesConfirmed;
    final providerComplete =
        progress.providerSetupOutcome != LibraryProviderSetupOutcome.pending;
    final providerStepReady = privacyComplete && metadataComplete;
    final rootStepReady = providerStepReady && providerComplete;
    final canFinish =
        privacyComplete &&
        metadataComplete &&
        providerComplete &&
        !state.requiresRootSelection;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Set up your Library',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text('Complete these choices before the first Library refresh.'),
        const SizedBox(height: 24),
        _Step(
          title: 'Privacy terms',
          complete: privacyComplete,
          action: !privacyComplete
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: submitting ? null : onAcceptPrivacy,
                      child: const Text('Accept current terms'),
                    ),
                    TextButton(
                      onPressed: submitting ? null : onDeclinePrivacy,
                      child: const Text('Decline and exit'),
                    ),
                  ],
                )
              : null,
        ),
        _Step(
          title: 'Metadata preferences',
          complete: metadataComplete,
          action: privacyComplete && !metadataComplete
              ? FilledButton(
                  onPressed: submitting ? null : onConfirmMetadata,
                  child: const Text('Use current preferences'),
                )
              : null,
        ),
        if (providerStepReady)
          _ProviderStep(
            readiness: snapshot.readiness,
            outcome: progress.providerSetupOutcome,
            submitting: submitting,
            onSetCredential: onSetCredential,
            onRecordConfigured: onRecordConfigured,
            onRemoveCredential: onRemoveCredential,
            onSkip: onSkipProvider,
          )
        else
          const _Step(title: 'Metadata providers', complete: false),
        if (rootStepReady)
          _Step(
            title: 'Library folder',
            complete: !state.requiresRootSelection,
            action: state.requiresRootSelection
                ? OutlinedButton.icon(
                    onPressed: submitting ? null : onAddRoot,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Add a Library folder'),
                  )
                : null,
          )
        else
          const _Step(title: 'Library folder', complete: false),
        if (canFinish) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: submitting ? null : onComplete,
            icon: const Icon(Icons.check),
            label: const Text('Finish & Refresh'),
          ),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onOpenSources,
          icon: const Icon(Icons.source_outlined),
          label: const Text('Open Sources'),
        ),
      ],
    );
  }
}

/// Supplies the current OS locale only when the backend has no saved choice.
MetadataSettings _metadataForConfirmation(
  MetadataSettings settings,
  Locale locale,
) {
  if (settings.preferredRegions.isNotEmpty ||
      settings.preferredLanguages.isNotEmpty) {
    return settings;
  }
  final region = locale.countryCode;
  return settings.copyWith(
    preferredRegions: region == null || region.isEmpty ? const [] : [region],
    preferredLanguages: [locale.languageCode],
  );
}

class _ProviderStep extends StatefulWidget {
  const _ProviderStep({
    required this.readiness,
    required this.outcome,
    required this.submitting,
    required this.onSetCredential,
    required this.onRecordConfigured,
    required this.onRemoveCredential,
    required this.onSkip,
  });

  final List<MetadataProviderReadiness> readiness;
  final LibraryProviderSetupOutcome outcome;
  final bool submitting;
  final Future<ProviderCredentialReadiness> Function(List<int>) onSetCredential;
  final Future<void> Function() onRecordConfigured;
  final Future<void> Function() onRemoveCredential;
  final VoidCallback onSkip;

  @override
  State<_ProviderStep> createState() => _ProviderStepState();
}

class _ProviderStepState extends State<_ProviderStep> {
  late final TextEditingController _controller;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  MetadataProviderReadiness? _provider(String id) {
    for (final provider in widget.readiness) {
      if (provider.providerId == id) return provider;
    }
    return null;
  }

  String _label(MetadataProviderReadiness? provider) {
    if (provider == null) return 'Unavailable';
    if (!provider.enabled) return 'Disabled';
    if (provider.capabilityReadiness.isEmpty) return 'Unavailable';
    return provider.capabilityReadiness
        .map((item) => _readinessLabel(item.state))
        .toSet()
        .join(', ');
  }

  Future<void> _submitCredential() async {
    final input = _controller.text;
    if (input.isEmpty) {
      setState(() => _notice = 'Enter a SteamGridDB API key.');
      return;
    }
    try {
      final readiness = await widget.onSetCredential(input.codeUnits);
      if (!mounted) return;
      final accepted =
          readiness.credentialConfigured &&
          (readiness.state == ProviderReadinessState.ready ||
              readiness.state == ProviderReadinessState.unavailable);
      if (accepted) {
        await widget.onRecordConfigured();
        if (mounted) setState(() => _notice = 'SteamGridDB is configured.');
      } else {
        setState(
          () => _notice =
              'SteamGridDB is not ready. Replace or remove this credential before skipping.',
        );
      }
    } on ClientFailure {
      if (mounted) {
        setState(() => _notice = 'SteamGridDB credential could not be saved.');
      }
    } finally {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final steam = _provider('steamgriddb');
    final credentialConfigured = steam?.credentialConfigured ?? false;
    final configuredOutcome =
        widget.outcome == LibraryProviderSetupOutcome.configured;
    final canSkip = !credentialConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Step(
          title: 'Metadata providers',
          complete:
              configuredOutcome ||
              widget.outcome == LibraryProviderSetupOutcome.skipped,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Playmatch: ${_label(_provider('playmatch'))}'),
              Text('GameTDB: ${_label(_provider('gametdb'))}'),
              const SizedBox(height: 8),
              Text('SteamGridDB: ${_label(steam)}'),
              if (!configuredOutcome) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  enabled: !widget.submitting,
                  decoration: const InputDecoration(
                    labelText: 'SteamGridDB API key',
                    helperText:
                        'The key is sent to secure storage and never read back.',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: widget.submitting ? null : _submitCredential,
                      child: Text(
                        credentialConfigured ? 'Replace key' : 'Save key',
                      ),
                    ),
                    if (credentialConfigured)
                      OutlinedButton(
                        onPressed: widget.submitting
                            ? null
                            : widget.onRemoveCredential,
                        child: const Text('Remove key'),
                      ),
                    if (canSkip)
                      TextButton(
                        onPressed: widget.submitting ? null : widget.onSkip,
                        child: const Text('Skip SteamGridDB'),
                      ),
                  ],
                ),
              ],
              if (_notice case final notice?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(notice),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _readinessLabel(ProviderReadinessState state) => switch (state) {
  ProviderReadinessState.ready => 'Ready',
  ProviderReadinessState.disabled => 'Disabled',
  ProviderReadinessState.missingCredentials => 'Credential required',
  ProviderReadinessState.invalidCredentials => 'Credential rejected',
  ProviderReadinessState.misconfigured => 'Misconfigured',
  ProviderReadinessState.unavailable => 'Temporarily unavailable',
};

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.complete, this.action});

  final String title;
  final bool complete;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            complete ? Icons.check_circle : Icons.radio_button_unchecked,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              if (action != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _OnboardingComplete extends StatelessWidget {
  const _OnboardingComplete({required this.onOpenLibrary});

  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 56),
          const SizedBox(height: 16),
          Text(
            'Library setup is complete',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenLibrary,
            icon: const Icon(Icons.grid_view),
            label: const Text('Open Library'),
          ),
        ],
      ),
    ),
  );
}
