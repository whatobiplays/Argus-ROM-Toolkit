import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_composition.dart';

/// Logical-library landing page. Only the unscoped baseline is queryable in
/// Phase 003; scoped routes retain their identity and render a truthful
/// controlled baseline until P03-007 activates scoped querying.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({
    required this.scope,
    required this.onOpenGame,
    required this.onOpenAll,
    required this.onOpenSources,
    required this.onOpenJob,
    super.key,
  });

  final LibraryScope scope;
  final void Function(GameId gameId) onOpenGame;
  final VoidCallback onOpenAll;
  final VoidCallback onOpenSources;
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  Future<_LibrarySnapshot>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.scope is LibraryScopeAll) {
      _future = _load();
    }
  }

  Future<_LibrarySnapshot> _load() async {
    final roots = await ref
        .read(librarySourcesApiProvider)
        .listLibraryRoots(offset: 0, pageSize: 50);
    final games = await ref
        .read(libraryApiProvider)
        .listGames(
          const ListGamesRequest(scope: LibraryScopeAll(), pageSize: 50),
        );
    return _LibrarySnapshot(roots: roots, games: games);
  }

  Future<void> _refresh() async {
    try {
      final handle = await ref.read(libraryRefreshApiProvider).refreshLibrary();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Library refresh started')));
      widget.onOpenJob(handle.jobRunId);
      if (!mounted) return;
      setState(() => _future = _load());
    } on ClientFailure {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The Library refresh could not start')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scope is! LibraryScopeAll) {
      return _ScopedLibraryBaseline(
        scope: widget.scope,
        onReturnToLibrary: widget.onOpenAll,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Library',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  FilledButton.icon(
                    key: const ValueKey<String>('library-refresh'),
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Library'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<_LibrarySnapshot>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || snapshot.data == null) {
                      return _LibraryLoadFailure(
                        onRetry: () => setState(() => _future = _load()),
                      );
                    }
                    return _LibraryContent(
                      snapshot: snapshot.data!,
                      onOpenGame: widget.onOpenGame,
                      onOpenSources: widget.onOpenSources,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySnapshot {
  const _LibrarySnapshot({required this.roots, required this.games});

  final LibraryRootPage roots;
  final GamePage games;
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.snapshot,
    required this.onOpenGame,
    required this.onOpenSources,
  });

  final _LibrarySnapshot snapshot;
  final void Function(GameId gameId) onOpenGame;
  final VoidCallback onOpenSources;

  @override
  Widget build(BuildContext context) {
    if (snapshot.roots.totalCount == 0) {
      return _LibraryEmptyState(
        icon: Icons.folder_open,
        title: 'Add a library root to begin',
        message:
            'Library games appear here after a configured source is scanned.',
        actionLabel: 'Open Sources',
        onAction: onOpenSources,
      );
    }
    if (snapshot.games.items.isEmpty) {
      return _LibraryEmptyState(
        icon: Icons.grid_view_outlined,
        title: 'No games yet',
        message:
            'Refresh the Library after your sources have finished scanning.',
        actionLabel: 'Open Sources',
        onAction: onOpenSources,
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('library-game-list'),
      itemCount: snapshot.games.items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final game = snapshot.games.items[index];
        return ListTile(
          key: ValueKey<String>('library-game-${game.gameId.value}'),
          leading: const Icon(Icons.videogame_asset_outlined),
          title: Text(game.displayTitle),
          subtitle: Text(
            '${_platformLabel(game.platformId)} · ${_hydrationLabel(game.hydrationState)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpenGame(game.gameId),
        );
      },
    );
  }
}

class _ScopedLibraryBaseline extends StatelessWidget {
  const _ScopedLibraryBaseline({
    required this.scope,
    required this.onReturnToLibrary,
  });

  final LibraryScope scope;
  final VoidCallback onReturnToLibrary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Scoped Library browsing is not available yet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The requested ${_scopeLabel(scope)} scope is preserved, but scoped querying is part of a later Library milestone. No unscoped games were loaded.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onReturnToLibrary,
                    icon: const Icon(Icons.grid_view),
                    label: const Text('View All Library Games'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.folder_outlined),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryLoadFailure extends StatelessWidget {
  const _LibraryLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('The Library could not be loaded.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

String _scopeLabel(LibraryScope scope) => switch (scope) {
  LibraryScopeAll() => 'all-games',
  LibraryScopePlatform(:final platformId) => 'platform $platformId',
  LibraryScopeSource(:final sourceId) => 'source $sourceId',
  LibraryScopeLibraryRoot(:final libraryRootId) =>
    'library root $libraryRootId',
};

String _platformLabel(PlatformId platform) => switch (platform) {
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

String _hydrationLabel(HydrationState state) => switch (state) {
  HydrationState.hydrated => 'Ready',
  HydrationState.partiallyHydrated => 'Partially enriched',
  HydrationState.unmatched => 'Needs identification',
  HydrationState.refreshing => 'Refreshing',
};
