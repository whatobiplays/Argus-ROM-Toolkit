import 'package:argus/core/client/client.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_composition.dart';
import 'appearance_messages.dart';
import 'theme_mode_control.dart';

/// Presents the real Phase 000 Appearance settings section.
///
/// Presentation watches the appearance controller and invokes only
/// [AppearanceSettingsController.selectThemeMode] and
/// [AppearanceSettingsController.retryAuthoritativeRead]; it never calls
/// client or bridge APIs directly.
class SettingsPage extends ConsumerWidget {
  /// Creates the Settings destination.
  const SettingsPage({this.onOpenJob, super.key});

  final void Function(JobRunId jobRunId)? onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);
    final gutter = pageGutterFor(sizeClass);
    final textTheme = Theme.of(context).textTheme;
    final appearance = ref.watch(appearanceSettingsControllerProvider);
    final state = appearance.value;
    final notifier = ref.read(appearanceSettingsControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text('Settings', style: textTheme.headlineMedium),
                  ),
                  const SizedBox(height: 16),
                  if (state == null)
                    Center(
                      child: Semantics(
                        liveRegion: true,
                        label: 'Loading appearance settings',
                        child: const CircularProgressIndicator(),
                      ),
                    )
                  else
                    _AppearanceSection(state: state, notifier: notifier),
                  if (ref.watch(settingsMetadataApiProvider) != null)
                    _MetadataPreferencesSection(onOpenJob: onOpenJob),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits the local metadata policy and provider enablement without owning any
/// refresh execution. The result of each commit is rendered independently so
/// a saved preference is never presented as an admitted resolution job.
class _MetadataPreferencesSection extends ConsumerStatefulWidget {
  const _MetadataPreferencesSection({required this.onOpenJob});

  final void Function(JobRunId jobRunId)? onOpenJob;

  @override
  ConsumerState<_MetadataPreferencesSection> createState() =>
      _MetadataPreferencesSectionState();
}

class _MetadataPreferencesSectionState
    extends ConsumerState<_MetadataPreferencesSection> {
  late Future<_MetadataPreferencesSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MetadataPreferencesSnapshot> _load() async {
    final api = ref.read(settingsMetadataApiProvider);
    if (api == null) {
      throw StateError('metadata settings capability is unavailable');
    }
    return _MetadataPreferencesSnapshot(
      settings: await api.getMetadataSettings(),
      providers: await api.getMetadataProviderSettings(),
      readiness: ref.read(settingsMetadataProvidersApiProvider) == null
          ? const <MetadataProviderReadiness>[]
          : await ref
                .read(settingsMetadataProvidersApiProvider)!
                .listMetadataProviderReadiness(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(settingsMetadataApiProvider);
    if (api == null) return const SizedBox.shrink();
    return FutureBuilder<_MetadataPreferencesSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 28),
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Metadata preferences could not be loaded.'),
                TextButton(
                  onPressed: () => setState(() => _future = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 28),
          child: _MetadataPreferencesEditor(
            snapshot: snapshot.data!,
            api: api,
            providersApi: ref.read(settingsMetadataProvidersApiProvider),
            onOpenJob: widget.onOpenJob,
          ),
        );
      },
    );
  }
}

final class _MetadataPreferencesSnapshot {
  const _MetadataPreferencesSnapshot({
    required this.settings,
    required this.providers,
    required this.readiness,
  });

  final MetadataSettings settings;
  final MetadataProviderSettings providers;
  final List<MetadataProviderReadiness> readiness;
}

class _MetadataPreferencesEditor extends StatefulWidget {
  const _MetadataPreferencesEditor({
    required this.snapshot,
    required this.api,
    required this.providersApi,
    this.onOpenJob,
  });

  final _MetadataPreferencesSnapshot snapshot;
  final MetadataSettingsApi api;
  final MetadataProvidersApi? providersApi;
  final void Function(JobRunId jobRunId)? onOpenJob;

  @override
  State<_MetadataPreferencesEditor> createState() =>
      _MetadataPreferencesEditorState();
}

class _MetadataPreferencesEditorState
    extends State<_MetadataPreferencesEditor> {
  static const _providers = <(String, String)>[
    ('playmatch', 'Playmatch'),
    ('gametdb', 'GameTDB'),
    ('steamgriddb', 'SteamGridDB'),
  ];

  late final TextEditingController _regionsController;
  late final TextEditingController _languagesController;
  late final TextEditingController _credentialController;
  late MetadataProviderSettings _providersState;
  late List<MetadataProviderReadiness> _readiness;
  bool _saving = false;
  String? _notice;
  JobRunId? _noticeJobRunId;

  @override
  void initState() {
    super.initState();
    _regionsController = TextEditingController(
      text: widget.snapshot.settings.preferredRegions.join(', '),
    );
    _languagesController = TextEditingController(
      text: widget.snapshot.settings.preferredLanguages.join(', '),
    );
    _credentialController = TextEditingController();
    _providersState = widget.snapshot.providers;
    _readiness = widget.snapshot.readiness;
  }

  @override
  void didUpdateWidget(covariant _MetadataPreferencesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _regionsController.text = widget.snapshot.settings.preferredRegions.join(
        ', ',
      );
      _languagesController.text = widget.snapshot.settings.preferredLanguages
          .join(', ');
      _providersState = widget.snapshot.providers;
      _readiness = widget.snapshot.readiness;
    }
  }

  @override
  void dispose() {
    _regionsController.dispose();
    _languagesController.dispose();
    _credentialController.dispose();
    super.dispose();
  }

  Future<void> _saveMetadata() async {
    final settings = MetadataSettings(
      preferredRegions: _split(_regionsController.text),
      preferredLanguages: _split(_languagesController.text),
    );
    await _run(() async {
      final result = await widget.api.updateMetadataSettings(settings);
      if (!mounted) return;
      switch (result) {
        case MetadataSettingsUpdateResultCommittedNoResolutionWork():
          _setNotice('Metadata preferences saved. No local resolution needed.');
        case MetadataSettingsUpdateResultCommittedAndResolutionAdmitted(
          :final handle,
        ):
          _setNotice('Metadata preferences saved. Local resolution started.');
          _openJob(handle.jobRunId);
        case MetadataSettingsUpdateResultCommittedButResolutionNotAdmitted():
          _setNotice(
            'Metadata preferences saved, but local resolution could not start.',
          );
      }
    });
  }

  Future<void> _saveProvider(String providerId, bool enabled) async {
    final enabledProviders = {..._providersState.enabledProviders};
    if (enabled) {
      enabledProviders.add(providerId);
    } else {
      enabledProviders.remove(providerId);
    }
    final settings = MetadataProviderSettings(
      enabledProviders: enabledProviders.toList()..sort(),
    );
    await _run(() async {
      final result = await widget.api.updateMetadataProviderSettings(settings);
      if (!mounted) return;
      switch (result) {
        case MetadataProviderSettingsUpdateResultCommittedNoResolutionWork(
          :final settings,
        ):
          _providersState = settings;
          _setNotice('Provider preferences saved.');
        case MetadataProviderSettingsUpdateResultCommittedAndResolutionAdmitted(
          :final settings,
          :final handle,
        ):
          _providersState = settings;
          _setNotice('Provider preferences saved. Local resolution started.');
          _openJob(handle.jobRunId);
        case MetadataProviderSettingsUpdateResultCommittedButResolutionNotAdmitted(
          :final settings,
        ):
          _providersState = settings;
          _setNotice(
            'Provider preferences saved, but local resolution could not start.',
          );
      }
      if (mounted) setState(() {});
    });
  }

  MetadataProviderReadiness? _readinessFor(String providerId) {
    for (final readiness in _readiness) {
      if (readiness.providerId == providerId) return readiness;
    }
    return null;
  }

  void _applyCredentialReadiness(ProviderCredentialReadiness result) {
    final current = _readinessFor(result.providerId);
    if (current == null) return;
    final capabilities = [
      for (final capability in current.capabilityReadiness)
        ProviderCapabilityReadiness(
          capability: capability.capability,
          state: result.state,
        ),
    ];
    setState(() {
      _readiness = [
        for (final provider in _readiness)
          provider.providerId == result.providerId
              ? MetadataProviderReadiness(
                  providerId: provider.providerId,
                  enabled: provider.enabled,
                  capabilityReadiness: capabilities,
                  credentialConfigured: result.credentialConfigured,
                )
              : provider,
      ];
    });
  }

  Future<void> _saveCredential() async {
    final providersApi = widget.providersApi;
    final secret = _credentialController.text;
    if (providersApi == null || secret.isEmpty) return;
    await _run(() async {
      try {
        final result = await providersApi.setSteamgriddbCredential(
          secret.codeUnits,
        );
        _applyCredentialReadiness(result);
        _setNotice(
          result.state == ProviderReadinessState.invalidCredentials ||
                  result.state == ProviderReadinessState.misconfigured
              ? 'SteamGridDB credential was rejected. Replace or remove it.'
              : 'SteamGridDB credential saved securely.',
        );
      } finally {
        _credentialController.clear();
      }
    });
  }

  Future<void> _removeCredential() async {
    final providersApi = widget.providersApi;
    if (providersApi == null) return;
    await _run(() async {
      final result = await providersApi.removeSteamgriddbCredential();
      _applyCredentialReadiness(result);
      _credentialController.clear();
      _setNotice('SteamGridDB credential removed.');
    });
  }

  String _readinessLabel(ProviderReadinessState state) => switch (state) {
    ProviderReadinessState.ready => 'Ready',
    ProviderReadinessState.disabled => 'Disabled',
    ProviderReadinessState.missingCredentials => 'Credential required',
    ProviderReadinessState.invalidCredentials => 'Credential rejected',
    ProviderReadinessState.misconfigured => 'Misconfigured',
    ProviderReadinessState.unavailable => 'Temporarily unavailable',
  };

  String _providerStatus(String providerId) {
    final readiness = _readinessFor(providerId);
    if (readiness == null) return 'Unavailable';
    if (!readiness.enabled) return 'Disabled';
    if (readiness.capabilityReadiness.isEmpty) return 'Unavailable';
    return readiness.capabilityReadiness
        .map((item) => _readinessLabel(item.state))
        .toSet()
        .join(', ');
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _notice = null;
      _noticeJobRunId = null;
    });
    try {
      await operation();
    } on ClientFailure {
      if (mounted) _setNotice('The metadata preference could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setNotice(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  void _openJob(JobRunId jobRunId) {
    if (mounted) setState(() => _noticeJobRunId = jobRunId);
    widget.onOpenJob?.call(jobRunId);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Metadata', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _regionsController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Preferred regions',
            hintText: 'us, eu',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _languagesController,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Preferred languages',
            hintText: 'en, ja',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveMetadata,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save metadata preferences'),
        ),
        const SizedBox(height: 20),
        Text('Providers', style: textTheme.titleMedium),
        ..._providers.map(
          (provider) => SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(provider.$2),
            subtitle: Text(_providerStatus(provider.$1)),
            value: _providersState.enabledProviders.contains(provider.$1),
            onChanged: _saving
                ? null
                : (enabled) => _saveProvider(provider.$1, enabled),
          ),
        ),
        if (widget.providersApi != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _credentialController,
            enabled: !_saving,
            obscureText: true,
            decoration: InputDecoration(
              labelText:
                  _readinessFor('steamgriddb')?.credentialConfigured == true
                  ? 'Replace SteamGridDB API key'
                  : 'SteamGridDB API key',
              helperText: 'Stored securely; the key cannot be revealed here.',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _saveCredential,
                icon: const Icon(Icons.key_outlined),
                label: Text(
                  _readinessFor('steamgriddb')?.credentialConfigured == true
                      ? 'Replace key'
                      : 'Save key',
                ),
              ),
              if (_readinessFor('steamgriddb')?.credentialConfigured == true)
                OutlinedButton.icon(
                  onPressed: _saving ? null : _removeCredential,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove key'),
                ),
            ],
          ),
        ],
        if (_notice case final notice?) ...[
          const SizedBox(height: 8),
          Text(notice),
          if (_noticeJobRunId case final jobRunId?)
            TextButton.icon(
              onPressed: () => widget.onOpenJob?.call(jobRunId),
              icon: const Icon(Icons.work_outline),
              label: const Text('Open resolution job'),
            ),
        ],
      ],
    );
  }
}

List<String> _split(String value) => [
  for (final item in value.split(','))
    if (item.trim().isNotEmpty) item.trim(),
];

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.state, required this.notifier});

  final AppearanceSettingsState state;
  final AppearanceSettingsController notifier;

  @override
  Widget build(BuildContext context) {
    final save = state.saveOperation;
    final synchronization = state.synchronization;
    final enabled =
        synchronization is AppearanceSynchronizationSynchronized &&
        save is! AppearanceSaveOperationSaving &&
        save is! AppearanceSaveOperationOutcomeUnknown &&
        save is! AppearanceSaveOperationCommittedButUnreconciled;
    final textTheme = Theme.of(context).textTheme;
    final saveFailure = switch (save) {
      AppearanceSaveOperationFailed(:final failure) => failure,
      AppearanceSaveOperationOutcomeUnknown(:final failure) => failure,
      AppearanceSaveOperationCommittedButUnreconciled(:final failure) =>
        failure,
      AppearanceSaveOperationIdle() || AppearanceSaveOperationSaving() => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Appearance', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        ThemeModeControl(
          selectedMode: state.presented.themeMode,
          enabled: enabled,
          onChanged: notifier.selectThemeMode,
        ),
        const SizedBox(height: 8),
        if (save is AppearanceSaveOperationSaving)
          Semantics(
            liveRegion: true,
            label: 'Saving appearance settings',
            child: Text(
              'Saving appearance settings…',
              style: textTheme.bodyMedium,
            ),
          ),
        if (saveFailure != null)
          Semantics(
            liveRegion: true,
            label: appearanceSaveFailureMessage(saveFailure),
            child: Text(
              appearanceSaveFailureMessage(saveFailure),
              style: textTheme.bodyMedium,
            ),
          ),
        if (synchronization is AppearanceSynchronizationUncertain) ...<Widget>[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label: appearanceUncertainMessage,
            child: Text(
              appearanceUncertainMessage,
              style: textTheme.bodyMedium,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: notifier.retryAuthoritativeRead,
              child: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
