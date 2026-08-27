import 'dart:async';
import 'dart:typed_data';

import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/window_size_class.dart';
import '../application/game_detail_controller.dart';
import '../library_composition.dart';

/// Focused durable Game detail route with explicit redirect and refresh
/// handling. Presentation never invents a replacement identity.
class GameDetailPage extends ConsumerStatefulWidget {
  const GameDetailPage({
    required this.gameId,
    required this.onMissingGame,
    required this.onOpenGame,
    required this.onOpenJob,
    super.key,
  });

  final GameId gameId;
  final VoidCallback onMissingGame;
  final void Function(GameId gameId) onOpenGame;
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  late final ArtworkBytesCache _artworkCache;

  @override
  void initState() {
    super.initState();
    _artworkCache = ArtworkBytesCache(api: ref.read(libraryArtworkApiProvider));
  }

  Future<void> _refresh(
    GameDetailController controller,
    RefreshMode mode,
  ) async {
    try {
      final handle = await controller.refresh(mode);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Game refresh started')));
      widget.onOpenJob(handle.jobRunId);
    } on ClientFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(gameDetailControllerProvider(widget.gameId));
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final state = controller.state;
            return switch (state.phase) {
              GameDetailLoadPhase.preReady => const Center(
                child: Text(
                  'Game detail is available when the runtime is ready.',
                ),
              ),
              GameDetailLoadPhase.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              GameDetailLoadPhase.ready => _GameDetailBody(
                detail: state.detail!,
                artworkCache: _artworkCache,
                onRefresh: (mode) => _refresh(controller, mode),
              ),
              GameDetailLoadPhase.redirected => _GameRedirect(
                canonicalGameId: state.canonicalGameId!,
                onOpenGame: widget.onOpenGame,
              ),
              GameDetailLoadPhase.missing => _GameMissing(
                onBack: widget.onMissingGame,
              ),
              GameDetailLoadPhase.failed => _GameLoadFailure(
                failure: state.failure,
                onRetry: controller.reload,
              ),
            };
          },
        ),
      ),
    );
  }
}

/// Responsive detail layout bands shared by the page and its widget tests.
typedef GameDetailWidthClass = WindowSizeClass;

/// Maps the exact responsive contract widths to a detail layout band.
GameDetailWidthClass gameDetailWidthClassForWidth(double width) =>
    classifyWindowWidth(width);

class _GameDetailBody extends StatelessWidget {
  const _GameDetailBody({
    required this.detail,
    required this.artworkCache,
    required this.onRefresh,
  });

  final GameDetail detail;
  final ArtworkBytesCache artworkCache;
  final Future<void> Function(RefreshMode mode) onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final widthClass = gameDetailWidthClassForWidth(constraints.maxWidth);
      final overview = _OverviewSection(
        detail: detail,
        artworkCache: artworkCache,
        onRefresh: onRefresh,
      );
      final metadata = _DetailSection(
        title: 'Metadata',
        initiallyExpanded: true,
        child: _MetadataContent(metadata: detail.resolvedMetadata),
      );
      final files = _DetailSection(
        title: 'Files & Copies',
        initiallyExpanded: true,
        child: _FilesAndCopiesContent(detail: detail),
      );
      final artwork = _DetailSection(
        title: 'Artwork',
        child: _ArtworkContent(
          artwork: detail.resolvedArtwork,
          artworkCache: artworkCache,
          onRetry: () => onRefresh(RefreshMode.eligibleOnly),
        ),
      );
      final sources = _DetailSection(
        title: 'Sources / Availability',
        initiallyExpanded: true,
        child: _SourcesAvailabilityContent(detail: detail),
      );
      final activity = _DetailSection(
        title: 'Activity / History',
        child: const _ActivityContent(),
      );
      final provenance = _DetailSection(
        title: 'Technical provenance',
        child: _TechnicalProvenanceContent(detail: detail),
      );

      final primary = <Widget>[metadata, files, artwork];
      final secondary = <Widget>[sources, activity, provenance];
      final isWide = widthClass.index >= GameDetailWidthClass.expanded.index;

      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              overview,
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _withSpacing(primary),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _withSpacing(secondary),
                      ),
                    ),
                  ],
                )
              else
                ..._withSpacing([...primary, ...secondary]),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _withSpacing(List<Widget> sections) {
    final result = <Widget>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) result.add(const SizedBox(height: 12));
      result.add(sections[index]);
    }
    return result;
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.detail,
    required this.artworkCache,
    required this.onRefresh,
  });

  final GameDetail detail;
  final ArtworkBytesCache artworkCache;
  final Future<void> Function(RefreshMode mode) onRefresh;

  @override
  Widget build(BuildContext context) {
    final metadata = detail.resolvedMetadata;
    final title = metadata?.displayTitle ?? detail.fallbackTitle;
    final cover = _coverArtwork(detail.resolvedArtwork);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Overview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  height: 240,
                  child: cover == null
                      ? const _ArtworkPlaceholder(label: 'No cover artwork')
                      : _ArtworkAssetView(
                          artwork: cover,
                          cache: artworkCache,
                          prominent: true,
                          onRetry: () => onRefresh(RefreshMode.eligibleOnly),
                        ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        key: const ValueKey<String>('game-overview-title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_gamePlatform(detail.platformId)} · ${detail.gameId.value}',
                      ),
                      if (metadata?.presentationRegion case final region?)
                        Text('Region: $region'),
                      if (metadata?.presentationLanguages case final languages?
                          when languages.isNotEmpty)
                        Text('Languages: ${languages.join(', ')}'),
                      if (metadata?.description case final description?) ...[
                        const SizedBox(height: 12),
                        Text(description),
                      ],
                      const SizedBox(height: 16),
                      _FactRow(
                        label: 'Lifecycle',
                        value: _gameLifecycle(detail.lifecycle),
                      ),
                      _FactRow(
                        label: 'Hydration',
                        value: _gameHydration(detail.hydrationState),
                      ),
                      _FactRow(
                        label: 'Availability',
                        value: _availabilityLabel(detail.availabilityState),
                      ),
                      _FactRow(
                        label: 'Content units',
                        value: '${detail.content.length}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey<String>('game-refresh'),
                  onPressed: () =>
                      unawaited(onRefresh(RefreshMode.eligibleOnly)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Game'),
                ),
                PopupMenuButton<RefreshMode>(
                  key: const ValueKey<String>('game-force-refresh'),
                  tooltip: 'Advanced refresh actions',
                  onSelected: (mode) => unawaited(onRefresh(mode)),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: RefreshMode.force,
                      child: Text('Force Refresh'),
                    ),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.more_horiz),
                    label: Text('Advanced'),
                  ),
                ),
              ],
            ),
            if (detail.lifecycle == GameLifecycle.inactiveOrphan) ...[
              const SizedBox(height: 12),
              const _StatusBanner(
                icon: Icons.inventory_2_outlined,
                text:
                    'This inactive orphan is retained for historical inspection and is read-only.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: ValueKey<String>('game-section-$title'),
      initiallyExpanded: initiallyExpanded,
      title: Text(title),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [child],
    ),
  );
}

class _MetadataContent extends StatelessWidget {
  const _MetadataContent({required this.metadata});

  final ResolvedMetadata? metadata;

  @override
  Widget build(BuildContext context) {
    if (metadata == null) {
      return const Text('No resolved metadata is available yet.');
    }
    final value = metadata!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value.displayTitle case final title?)
          _FactRow(label: 'Title', value: title),
        if (value.sortTitle case final title?)
          _FactRow(label: 'Sort title', value: title),
        if (value.releaseDate case final date?)
          _FactRow(label: 'Release date', value: date),
        if (value.developers.isNotEmpty)
          _FactRow(label: 'Developers', value: value.developers.join(', ')),
        if (value.publishers.isNotEmpty)
          _FactRow(label: 'Publishers', value: value.publishers.join(', ')),
        if (value.genres.isNotEmpty)
          _FactRow(label: 'Genres', value: value.genres.join(', ')),
        if (value.fieldProvenance.isNotEmpty)
          ExpansionTile(
            title: const Text('Field provenance'),
            children: [
              for (final provenance in value.fieldProvenance)
                ListTile(
                  dense: true,
                  title: Text(provenance.field),
                  subtitle: Text(_provenanceLabel(provenance)),
                ),
            ],
          ),
        Text(
          'Resolution revision ${value.resolutionRevision}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _FilesAndCopiesContent extends StatelessWidget {
  const _FilesAndCopiesContent({required this.detail});

  final GameDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.content.isEmpty) {
      return const Text('No content units are currently associated.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final content in detail.content)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _contentTypeLabel(content.contentType),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    _FactRow(
                      label: 'Relationship',
                      value: _relationshipLabel(detail, content.gameContentId),
                    ),
                    _FactRow(
                      label: 'Presence',
                      value: _contentPresenceLabel(content.presence),
                    ),
                    _FactRow(
                      label: 'Identification',
                      value: _identificationLabel(content.identification),
                    ),
                    _FactRow(label: 'Copies', value: '${content.sourceCount}'),
                    if (content.sources.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      for (final source in content.sources)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.folder_copy_outlined),
                          title: Text(
                            '${source.sourceDisplayName} · ${source.rootDisplayName}',
                          ),
                          subtitle: Text(source.safeLocationPresentation),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SourcesAvailabilityContent extends StatelessWidget {
  const _SourcesAvailabilityContent({required this.detail});

  final GameDetail detail;

  @override
  Widget build(BuildContext context) {
    final sources = [for (final content in detail.content) ...content.sources];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FactRow(
          label: 'Game availability',
          value: _availabilityLabel(detail.availabilityState),
        ),
        if (sources.isEmpty)
          const Text('No current source presentation is available.')
        else
          for (final source in sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.source_outlined),
              title: Text(source.sourceDisplayName),
              subtitle: Text(
                '${source.rootDisplayName} · ${source.safeLocationPresentation}',
              ),
            ),
      ],
    );
  }
}

class _ArtworkContent extends StatelessWidget {
  const _ArtworkContent({
    required this.artwork,
    required this.artworkCache,
    required this.onRetry,
  });

  final List<ResolvedArtwork> artwork;
  final ArtworkBytesCache artworkCache;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (artwork.isEmpty) {
      return const Text('No selected artwork is available yet.');
    }
    final grouped = <String, List<ResolvedArtwork>>{};
    for (final value in artwork) {
      grouped.putIfAbsent(value.artworkType, () => []).add(value);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Text(
            _artworkTypeLabel(entry.key),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final value in entry.value)
                SizedBox(
                  width: value.artworkType == 'screenshot' ? 220 : 160,
                  child: _ArtworkAssetView(
                    artwork: value,
                    cache: artworkCache,
                    onRetry: onRetry,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ArtworkAssetView extends StatefulWidget {
  const _ArtworkAssetView({
    required this.artwork,
    required this.cache,
    required this.onRetry,
    this.prominent = false,
  });

  final ResolvedArtwork artwork;
  final ArtworkBytesCache cache;
  final VoidCallback onRetry;
  final bool prominent;

  @override
  State<_ArtworkAssetView> createState() => _ArtworkAssetViewState();
}

class _ArtworkAssetViewState extends State<_ArtworkAssetView> {
  Future<ArtworkAssetBytes>? _future;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant _ArtworkAssetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artwork.assetId != widget.artwork.assetId ||
        oldWidget.cache != widget.cache) {
      _startLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetId = widget.artwork.assetId;
    if (assetId == null) {
      return const _ArtworkPlaceholder(label: 'Artwork not downloaded');
    }
    return FutureBuilder<ArtworkAssetBytes>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ArtworkPlaceholder(label: 'Loading artwork…');
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ArtworkFailure(onRetry: widget.onRetry);
        }
        final asset = snapshot.data!;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            Uint8List.fromList(asset.bytes),
            fit: BoxFit.cover,
            semanticLabel:
                '${_artworkTypeLabel(widget.artwork.artworkType)} artwork',
            errorBuilder: (context, error, stackTrace) =>
                _ArtworkFailure(onRetry: widget.onRetry),
          ),
        );
      },
    );
  }

  void _startLoad() {
    final assetId = widget.artwork.assetId;
    _future = assetId == null ? null : widget.cache.load(assetId);
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined, size: 32),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _ArtworkFailure extends StatelessWidget {
  const _ArtworkFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Artwork unavailable', textAlign: TextAlign.center),
        TextButton(onPressed: onRetry, child: const Text('Retry enrichment')),
      ],
    ),
  );
}

class _ActivityContent extends StatelessWidget {
  const _ActivityContent();

  @override
  Widget build(BuildContext context) => const Text(
    'Refresh admissions and their progress are recorded in Jobs. Accepted refresh actions open the corresponding Job detail.',
  );
}

class _TechnicalProvenanceContent extends StatelessWidget {
  const _TechnicalProvenanceContent({required this.detail});

  final GameDetail detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final content in detail.content) ...[
        Text('Content ${content.gameContentId.value}'),
        if (content.identity case final identity?)
          _FactRow(
            label: 'Identity proof',
            value: '${identity.schemeId} revision ${identity.revision}',
          ),
        if (content.provenance case final provenance?)
          _FactRow(
            label: 'Provenance',
            value: '${provenance.members.length} normalized source member(s)',
          ),
        const SizedBox(height: 8),
      ],
      if (detail.resolvedMetadata case final metadata?)
        _FactRow(
          label: 'Metadata revision',
          value: '${metadata.resolutionRevision}',
        ),
      for (final artwork in detail.resolvedArtwork)
        _FactRow(
          label: _artworkTypeLabel(artwork.artworkType),
          value: artwork.selectionReason,
        ),
    ],
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _GameRedirect extends StatelessWidget {
  const _GameRedirect({
    required this.canonicalGameId,
    required this.onOpenGame,
  });

  final GameId canonicalGameId;
  final void Function(GameId gameId) onOpenGame;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('This Game has moved.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => onOpenGame(canonicalGameId),
          child: const Text('Open canonical Game'),
        ),
      ],
    ),
  );
}

class _GameMissing extends StatelessWidget {
  const _GameMissing({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Game not found'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to Library'),
        ),
      ],
    ),
  );
}

class _GameLoadFailure extends StatelessWidget {
  const _GameLoadFailure({required this.failure, required this.onRetry});

  final ClientFailure? failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(failure?.message ?? 'The Game detail could not be loaded.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => unawaited(onRetry()),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

ResolvedArtwork? _coverArtwork(List<ResolvedArtwork> artwork) {
  for (final value in artwork) {
    if (value.artworkType == 'cover_front') return value;
  }
  for (final value in artwork) {
    if (value.assetId != null) return value;
  }
  return artwork.isEmpty ? null : artwork.first;
}

String _provenanceLabel(MetadataFieldProvenance value) {
  if (value.providerId case final provider?) return 'Provided by $provider';
  return value.source;
}

String _relationshipLabel(GameDetail detail, ContentId contentId) {
  final relationships = detail.memberships
      .where((membership) => membership.gameContentId == contentId)
      .map(_membershipRelationshipLabel)
      .toList();
  return relationships.isEmpty
      ? 'Associated content'
      : relationships.join(', ');
}

String _membershipRelationshipLabel(GameMembershipSummary value) =>
    switch (value.relationship) {
      MembershipRelationship.primary => 'Primary',
      MembershipRelationship.secondary => 'Secondary',
      MembershipRelationship.primaryContent => 'Primary content',
      MembershipRelationship.regionalVariant => 'Regional variant',
      MembershipRelationship.languageVariant => 'Language variant',
      MembershipRelationship.revisionVariant => 'Revision variant',
      MembershipRelationship.disc => 'Disc',
      MembershipRelationship.equivalentReleaseRepresentation =>
        'Equivalent release representation',
    };

String _contentTypeLabel(ContentType value) => switch (value) {
  ContentType.cartridgeImage => 'Cartridge image',
  ContentType.magneticDiskImage => 'Magnetic disk image',
  ContentType.opticalDiscCd => 'Optical disc (CD)',
  ContentType.opticalDiscGd => 'Optical disc (GD)',
  ContentType.opticalDiscDvd => 'Optical disc (DVD)',
  ContentType.opticalDiscGameCube => 'Optical disc (GameCube)',
  ContentType.opticalDiscWii => 'Optical disc (Wii)',
  ContentType.opticalDiscUmd => 'Optical disc (UMD)',
};

String _contentPresenceLabel(ContentPresence value) => switch (value) {
  ContentPresence.available => 'Available',
  ContentPresence.partiallyUnavailable => 'Partially unavailable',
  ContentPresence.unavailable => 'Unavailable',
  ContentPresence.orphaned => 'Orphaned',
};

String _identificationLabel(IdentificationState value) => switch (value) {
  IdentificationState.identified => 'Identified',
  IdentificationState.needsReidentification => 'Needs re-identification',
  IdentificationState.unidentified => 'Unidentified',
};

String _artworkTypeLabel(String value) => switch (value) {
  'cover_front' => 'Front cover',
  'cover_back' => 'Back cover',
  'cover_spine' => 'Spine',
  'screenshot' => 'Screenshots',
  'title_screen' => 'Title screen',
  'logo' => 'Logo',
  'icon' => 'Icon',
  'background' => 'Background',
  'banner' => 'Banner',
  'manual' => 'Manual',
  _ => value,
};

String _gamePlatform(PlatformId platform) => switch (platform) {
  PlatformId.nintendoNes => 'Nintendo Entertainment System',
  PlatformId.nintendoFds => 'Nintendo Famicom Disk System',
  PlatformId.nintendoSnes => 'Super Nintendo Entertainment System',
  PlatformId.nintendoGb => 'Nintendo Game Boy',
  PlatformId.nintendoGbc => 'Nintendo Game Boy Color',
  PlatformId.nintendoGba => 'Nintendo Game Boy Advance',
  PlatformId.nintendoN64 => 'Nintendo 64',
  PlatformId.nintendoNds => 'Nintendo DS',
  PlatformId.nintendo3ds => 'Nintendo 3DS',
  PlatformId.segaSms => 'Sega Master System',
  PlatformId.segaGameGear => 'Sega Game Gear',
  PlatformId.segaGenesis => 'Sega Genesis',
  PlatformId.sega32x => 'Sega 32X',
  PlatformId.nintendoGameCube => 'Nintendo GameCube',
  PlatformId.nintendoWii => 'Nintendo Wii',
  PlatformId.segaCd => 'Sega CD',
  PlatformId.segaSaturn => 'Sega Saturn',
  PlatformId.segaDreamcast => 'Sega Dreamcast',
  PlatformId.sonyPlaystation => 'Sony PlayStation',
  PlatformId.sonyPlaystation2 => 'Sony PlayStation 2',
  PlatformId.sonyPsp => 'Sony PSP',
};

String _gameLifecycle(GameLifecycle lifecycle) => switch (lifecycle) {
  GameLifecycle.active => 'Active',
  GameLifecycle.inactiveOrphan => 'Inactive orphan',
  GameLifecycle.redirected => 'Redirected',
};

String _gameHydration(HydrationState state) => switch (state) {
  HydrationState.hydrated => 'Hydrated',
  HydrationState.partiallyHydrated => 'Partially hydrated',
  HydrationState.unmatched => 'Unmatched',
  HydrationState.refreshing => 'Refreshing',
};

String _availabilityLabel(AvailabilityState state) => switch (state) {
  AvailabilityState.available => 'Available',
  AvailabilityState.partiallyUnavailable => 'Partially unavailable',
  AvailabilityState.unavailable => 'Unavailable',
  AvailabilityState.inactiveOrphan => 'Inactive orphan',
};
