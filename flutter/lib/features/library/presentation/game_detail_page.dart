import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late Future<GetGameResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<GetGameResult> _load() =>
      ref.read(libraryGamesApiProvider).getGame(widget.gameId);

  Future<void> _refresh(RefreshMode mode) async {
    try {
      final handle = await ref
          .read(libraryGamesApiProvider)
          .refreshGame(gameId: widget.gameId, mode: mode);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Game refresh started')));
      widget.onOpenJob(handle.jobRunId);
    } on ClientFailure {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Game refresh could not start')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<GetGameResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _GameMissing(onBack: widget.onMissingGame);
            }
            return switch (snapshot.data!) {
              GetGameFound(:final detail) => _GameDetailBody(
                detail: detail,
                onRefresh: _refresh,
              ),
              GetGameRedirected(:final canonicalGameId) => _GameRedirect(
                canonicalGameId: canonicalGameId,
                onOpenGame: widget.onOpenGame,
              ),
            };
          },
        ),
      ),
    );
  }
}

class _GameDetailBody extends StatelessWidget {
  const _GameDetailBody({required this.detail, required this.onRefresh});

  final GameDetail detail;
  final Future<void> Function(RefreshMode mode) onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          detail.fallbackTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text('${detail.gameId.value} · ${_gamePlatform(detail.platformId)}'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey<String>('game-refresh'),
              onPressed: () => onRefresh(RefreshMode.eligibleOnly),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Game'),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('game-force-refresh'),
              onPressed: () => onRefresh(RefreshMode.force),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Force Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _FactRow(label: 'Status', value: _gameLifecycle(detail.lifecycle)),
        _FactRow(
          label: 'Hydration',
          value: _gameHydration(detail.hydrationState),
        ),
        _FactRow(label: 'Content units', value: '${detail.content.length}'),
        if (detail.resolvedMetadata case final metadata?) ...[
          const SizedBox(height: 24),
          Text('Metadata', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (metadata.displayTitle case final title?) Text(title),
          if (metadata.releaseDate case final releaseDate?)
            Text('Released $releaseDate'),
          if (metadata.description case final description?) ...[
            const SizedBox(height: 8),
            Text(description),
          ],
        ],
        if (detail.resolvedMetadata == null) ...[
          const SizedBox(height: 24),
          const Text('No resolved metadata is available yet.'),
        ],
      ],
    );
  }
}

class _GameRedirect extends StatelessWidget {
  const _GameRedirect({
    required this.canonicalGameId,
    required this.onOpenGame,
  });

  final GameId canonicalGameId;
  final void Function(GameId gameId) onOpenGame;

  @override
  Widget build(BuildContext context) {
    return Center(
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
}

class _GameMissing extends StatelessWidget {
  const _GameMissing({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
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
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 130, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _gamePlatform(PlatformId platform) => switch (platform) {
  PlatformId.nintendoGb => 'Nintendo Game Boy',
  PlatformId.nintendoGbc => 'Nintendo Game Boy Color',
  PlatformId.nintendoGba => 'Nintendo Game Boy Advance',
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
