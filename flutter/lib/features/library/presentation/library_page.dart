import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/window_size_class.dart';
import '../application/library_controller.dart';
import '../application/library_state.dart';
import '../library_composition.dart';

/// Route-owned logical-library browser.
///
/// The page renders backend-provided rows and facet counts. Search, filters,
/// sorting, continuation, and eligibility remain owned by the Library client
/// contract; this widget only coordinates presentation and user intent.
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
  late final TextEditingController _searchController;
  late final ScrollController _gridScrollController;
  late final ScrollController _listScrollController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _gridScrollController = ScrollController()..addListener(_loadMoreNearEnd);
    _listScrollController = ScrollController()..addListener(_loadMoreNearEnd);
  }

  @override
  void dispose() {
    _gridScrollController
      ..removeListener(_loadMoreNearEnd)
      ..dispose();
    _listScrollController
      ..removeListener(_loadMoreNearEnd)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadMoreNearEnd() {
    final controller = ref.read(libraryControllerProvider(widget.scope));
    final scrollController = controller.state.viewMode == LibraryViewMode.grid
        ? _gridScrollController
        : _listScrollController;
    if (!scrollController.hasClients ||
        scrollController.position.extentAfter > 480) {
      return;
    }
    controller.setScrollOffset(scrollController.offset);
    unawaited(controller.loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(libraryControllerProvider(widget.scope));
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        if (_searchController.text != (state.searchText ?? '')) {
          _searchController.value = TextEditingValue(
            text: state.searchText ?? '',
            selection: TextSelection.collapsed(
              offset: (state.searchText ?? '').length,
            ),
          );
        }
        return PopScope<void>(
          canPop: state.selectedGameIds.isEmpty,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && state.selectedGameIds.isNotEmpty) {
              controller.clearSelection();
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final widthClass = libraryWidthClassForWidth(
                    constraints.maxWidth,
                  );
                  return Column(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            _LibraryHeader(
                              scope: widget.scope,
                              state: state,
                              widthClass: widthClass,
                              searchController: _searchController,
                              onSearchChanged: controller.setSearchText,
                              onRefreshLibrary: () => _refreshLibrary(context),
                              onRefreshSelected: () =>
                                  _refreshSelected(context, controller),
                              onViewModeChanged: controller.setViewMode,
                              onSortChanged: controller.setSort,
                            ),
                            _LibraryFilters(
                              state: state,
                              onFiltersChanged: controller.setFilters,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _LibraryBody(
                          scope: widget.scope,
                          state: state,
                          controller: controller,
                          gridScrollController: _gridScrollController,
                          listScrollController: _listScrollController,
                          widthClass: widthClass,
                          onOpenGame: widget.onOpenGame,
                          onOpenSources: widget.onOpenSources,
                          onForceRefresh: (gameId) =>
                              _forceRefresh(context, controller, gameId),
                          onRetry: controller.refresh,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshLibrary(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final handle = await ref.read(libraryRefreshApiProvider).refreshLibrary();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Library refresh started')),
      );
      widget.onOpenJob(handle.jobRunId);
    } on ClientFailure catch (failure) {
      if (!mounted) return;
      _showFailure(messenger, failure, 'The Library refresh could not start');
    }
  }

  Future<void> _refreshSelected(
    BuildContext context,
    LibraryController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final handle = await controller.refreshSelected();
      if (!mounted) return;
      if (handle == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Select between 1 and 64 Games to refresh with EligibleOnly.',
            ),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Selected Game refresh started')),
      );
      widget.onOpenJob(handle.jobRunId);
    } on ClientFailure catch (failure) {
      if (!mounted) return;
      _showFailure(messenger, failure, 'Selected Game refresh could not start');
    }
  }

  Future<void> _forceRefresh(
    BuildContext context,
    LibraryController controller,
    GameId gameId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final handle = await controller.forceRefresh(gameId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Game force refresh started')),
      );
      widget.onOpenJob(handle.jobRunId);
    } on ClientFailure catch (failure) {
      if (!mounted) return;
      _showFailure(
        messenger,
        failure,
        'The Game force refresh could not start',
      );
    }
  }

  void _showFailure(
    ScaffoldMessengerState messenger,
    ClientFailure failure,
    String fallback,
  ) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(failure.message.isEmpty ? fallback : failure.message),
      ),
    );
  }
}

typedef LibraryWidthClass = WindowSizeClass;

LibraryWidthClass libraryWidthClassForWidth(double width) =>
    classifyWindowWidth(width);

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.scope,
    required this.state,
    required this.widthClass,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRefreshLibrary,
    required this.onRefreshSelected,
    required this.onViewModeChanged,
    required this.onSortChanged,
  });

  final LibraryScope scope;
  final LibraryState state;
  final LibraryWidthClass widthClass;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefreshLibrary;
  final VoidCallback onRefreshSelected;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final ValueChanged<LibrarySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final hasSelection = state.selectedGameIds.isNotEmpty;
    final canRefreshSelected =
        hasSelection &&
        state.selectedGameIds.length <= LibraryController.maxRefreshSelected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: widthClass == LibraryWidthClass.compact ? 12 : 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _scopeTitle(scope),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (state.refreshing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              FilledButton.icon(
                key: const ValueKey<String>('library-refresh'),
                onPressed: onRefreshLibrary,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Library'),
              ),
              FilledButton.icon(
                key: const ValueKey<String>('library-refresh-selected'),
                onPressed: canRefreshSelected ? onRefreshSelected : null,
                icon: const Icon(Icons.playlist_play),
                label: Text(
                  hasSelection
                      ? 'Refresh Selected (${state.selectedGameIds.length})'
                      : 'Refresh Selected',
                ),
              ),
              SegmentedButton<LibraryViewMode>(
                key: const ValueKey<String>('library-view-mode'),
                segments: const [
                  ButtonSegment(
                    value: LibraryViewMode.grid,
                    icon: Icon(Icons.grid_view),
                    label: Text('Grid'),
                  ),
                  ButtonSegment(
                    value: LibraryViewMode.list,
                    icon: Icon(Icons.view_list),
                    label: Text('List'),
                  ),
                ],
                selected: {state.viewMode},
                onSelectionChanged: (selection) =>
                    onViewModeChanged(selection.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widthClass == LibraryWidthClass.compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _searchField(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [_sortField(), _sortDirectionButton()],
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _searchField()),
                const SizedBox(width: 12),
                _sortField(),
                _sortDirectionButton(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _searchField() => TextField(
    key: const ValueKey<String>('library-search'),
    controller: searchController,
    onChanged: onSearchChanged,
    textInputAction: TextInputAction.search,
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      prefixIcon: Icon(Icons.search),
      hintText: 'Search title, alternate title, or platform',
      labelText: 'Search Library',
    ),
  );

  Widget _sortField() => DropdownButton<LibrarySortField>(
    value: state.sort.field,
    onChanged: (field) {
      if (field == null) return;
      onSortChanged(LibrarySort(field: field, direction: state.sort.direction));
    },
    items: const [
      DropdownMenuItem(
        value: LibrarySortField.displayTitle,
        child: Text('Title'),
      ),
      DropdownMenuItem(
        value: LibrarySortField.platform,
        child: Text('Platform'),
      ),
      DropdownMenuItem(
        value: LibrarySortField.releaseDate,
        child: Text('Release date'),
      ),
      DropdownMenuItem(
        value: LibrarySortField.updatedAt,
        child: Text('Updated'),
      ),
    ],
  );

  Widget _sortDirectionButton() => IconButton(
    tooltip: state.sort.direction == LibrarySortDirection.ascending
        ? 'Ascending'
        : 'Descending',
    onPressed: () => onSortChanged(
      LibrarySort(
        field: state.sort.field,
        direction: state.sort.direction == LibrarySortDirection.ascending
            ? LibrarySortDirection.descending
            : LibrarySortDirection.ascending,
      ),
    ),
    icon: Icon(
      state.sort.direction == LibrarySortDirection.ascending
          ? Icons.arrow_upward
          : Icons.arrow_downward,
    ),
  );
}

class _LibraryFilters extends StatelessWidget {
  const _LibraryFilters({required this.state, required this.onFiltersChanged});

  final LibraryState state;
  final ValueChanged<LibraryFilter> onFiltersChanged;

  @override
  Widget build(BuildContext context) {
    final facets = state.facets;
    if (facets == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          for (final bucket in facets.platforms)
            _platformChip(bucket, state.filters),
          for (final bucket in facets.regions)
            _regionChip(bucket, state.filters),
          for (final bucket in facets.hydrationStates)
            _hydrationChip(bucket, state.filters),
          for (final bucket in facets.availabilityStates)
            _availabilityChip(bucket, state.filters),
        ],
      ),
    );
  }

  Widget _platformChip(PlatformFacetBucket bucket, LibraryFilter filters) {
    final wire = _platformWire(bucket.platformId);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          '${_platformShortLabel(bucket.platformId)} (${bucket.count})',
        ),
        selected: filters.platformIds.contains(wire),
        onSelected: (_) => onFiltersChanged(
          _withStringFilter(filters, wire, FilterDimension.platform),
        ),
      ),
    );
  }

  Widget _regionChip(RegionFacetBucket bucket, LibraryFilter filters) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('${bucket.region.toUpperCase()} (${bucket.count})'),
        selected: filters.regions.contains(bucket.region),
        onSelected: (_) => onFiltersChanged(
          _withStringFilter(filters, bucket.region, FilterDimension.region),
        ),
      ),
    );
  }

  Widget _hydrationChip(
    HydrationStateFacetBucket bucket,
    LibraryFilter filters,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          '${_hydrationLabel(bucket.hydrationState)} (${bucket.count})',
        ),
        selected: filters.hydrationStates.contains(bucket.hydrationState),
        onSelected: (_) => onFiltersChanged(
          _withHydrationFilter(filters, bucket.hydrationState),
        ),
      ),
    );
  }

  Widget _availabilityChip(
    AvailabilityStateFacetBucket bucket,
    LibraryFilter filters,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          '${_availabilityLabel(bucket.availabilityState)} (${bucket.count})',
        ),
        selected: filters.availabilityStates.contains(bucket.availabilityState),
        onSelected: (_) => onFiltersChanged(
          _withAvailabilityFilter(filters, bucket.availabilityState),
        ),
      ),
    );
  }
}

enum FilterDimension { platform, region }

LibraryFilter _withStringFilter(
  LibraryFilter filters,
  String value,
  FilterDimension dimension,
) {
  final values = dimension == FilterDimension.platform
      ? {...filters.platformIds}
      : {...filters.regions};
  if (!values.add(value)) values.remove(value);
  return dimension == FilterDimension.platform
      ? LibraryFilter(
          platformIds: values.toList(),
          regions: filters.regions,
          hydrationStates: filters.hydrationStates,
          availabilityStates: filters.availabilityStates,
        )
      : LibraryFilter(
          platformIds: filters.platformIds,
          regions: values.toList(),
          hydrationStates: filters.hydrationStates,
          availabilityStates: filters.availabilityStates,
        );
}

LibraryFilter _withHydrationFilter(
  LibraryFilter filters,
  HydrationState value,
) {
  final values = {...filters.hydrationStates};
  if (!values.add(value)) values.remove(value);
  return LibraryFilter(
    platformIds: filters.platformIds,
    regions: filters.regions,
    hydrationStates: values.toList(),
    availabilityStates: filters.availabilityStates,
  );
}

LibraryFilter _withAvailabilityFilter(
  LibraryFilter filters,
  AvailabilityState value,
) {
  final values = {...filters.availabilityStates};
  if (!values.add(value)) values.remove(value);
  return LibraryFilter(
    platformIds: filters.platformIds,
    regions: filters.regions,
    hydrationStates: filters.hydrationStates,
    availabilityStates: values.toList(),
  );
}

void _activateLibraryGame({
  required LibraryState state,
  required LibraryController controller,
  required GameId gameId,
  required void Function(GameId gameId) onOpen,
}) {
  final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
  final shiftPressed =
      pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
      pressedKeys.contains(LogicalKeyboardKey.shiftRight);
  final togglePressed =
      pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
      pressedKeys.contains(LogicalKeyboardKey.controlRight) ||
      pressedKeys.contains(LogicalKeyboardKey.metaLeft) ||
      pressedKeys.contains(LogicalKeyboardKey.metaRight);
  if (shiftPressed) {
    controller.selectRange(gameId);
  } else if (togglePressed || state.selectedGameIds.contains(gameId)) {
    controller.toggleSelection(gameId);
  } else {
    onOpen(gameId);
  }
}

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.scope,
    required this.state,
    required this.controller,
    required this.gridScrollController,
    required this.listScrollController,
    required this.widthClass,
    required this.onOpenGame,
    required this.onOpenSources,
    required this.onForceRefresh,
    required this.onRetry,
  });

  final LibraryScope scope;
  final LibraryState state;
  final LibraryController controller;
  final ScrollController gridScrollController;
  final ScrollController listScrollController;
  final LibraryWidthClass widthClass;
  final void Function(GameId gameId) onOpenGame;
  final VoidCallback onOpenSources;
  final Future<void> Function(GameId gameId) onForceRefresh;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.phase == LibraryLoadPhase.failed && state.games.isEmpty) {
      return _LibraryLoadFailure(onRetry: onRetry);
    }
    if (state.phase == LibraryLoadPhase.loading && state.games.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final roots = state.roots;
    if (scope is LibraryScopeAll && roots != null && roots.totalCount == 0) {
      return _LibraryEmptyState(
        icon: Icons.folder_open,
        title: 'Add a library root to begin',
        message:
            'Library games appear here after a configured source is scanned.',
        actionLabel: 'Open Sources',
        onAction: onOpenSources,
      );
    }
    if (state.games.isEmpty) {
      return _LibraryEmptyState(
        icon: Icons.grid_view_outlined,
        title: 'No games match this query',
        message: state.searchText?.isNotEmpty == true
            ? 'Try a different search or remove a filter.'
            : 'Refresh the Library after your sources have finished scanning.',
        actionLabel: 'Open Sources',
        onAction: onOpenSources,
      );
    }
    return state.viewMode == LibraryViewMode.grid
        ? _LibraryGrid(
            state: state,
            controller: controller,
            scrollController: gridScrollController,
            widthClass: widthClass,
            onOpenGame: onOpenGame,
            onForceRefresh: onForceRefresh,
          )
        : _LibraryList(
            state: state,
            controller: controller,
            scrollController: listScrollController,
            onOpenGame: onOpenGame,
            onForceRefresh: onForceRefresh,
          );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.state,
    required this.controller,
    required this.scrollController,
    required this.widthClass,
    required this.onOpenGame,
    required this.onForceRefresh,
  });

  final LibraryState state;
  final LibraryController controller;
  final ScrollController scrollController;
  final LibraryWidthClass widthClass;
  final void Function(GameId gameId) onOpenGame;
  final Future<void> Function(GameId gameId) onForceRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = switch (widthClass) {
        LibraryWidthClass.compact => 2,
        LibraryWidthClass.medium => 3,
        LibraryWidthClass.expanded => 4,
        LibraryWidthClass.large => 5,
      };
      return GridView.builder(
        key: const PageStorageKey<String>('library-game-grid'),
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: widthClass.index >= LibraryWidthClass.expanded.index
              ? 1.15
              : 0.95,
        ),
        itemCount: state.games.length,
        itemBuilder: (context, index) => _GameCard(
          game: state.games[index],
          selected: state.selectedGameIds.contains(state.games[index].gameId),
          grid: true,
          onOpen: onOpenGame,
          onTap: (gameId) => _activateLibraryGame(
            state: state,
            controller: controller,
            gameId: gameId,
            onOpen: onOpenGame,
          ),
          onToggleSelection: controller.toggleSelection,
          onForceRefresh: onForceRefresh,
        ),
      );
    },
  );
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.state,
    required this.controller,
    required this.scrollController,
    required this.onOpenGame,
    required this.onForceRefresh,
  });

  final LibraryState state;
  final LibraryController controller;
  final ScrollController scrollController;
  final void Function(GameId gameId) onOpenGame;
  final Future<void> Function(GameId gameId) onForceRefresh;

  @override
  Widget build(BuildContext context) => ListView.separated(
    key: const PageStorageKey<String>('library-game-list'),
    controller: scrollController,
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    itemCount: state.games.length,
    separatorBuilder: (context, index) => const SizedBox(height: 8),
    itemBuilder: (context, index) => _GameCard(
      game: state.games[index],
      selected: state.selectedGameIds.contains(state.games[index].gameId),
      grid: false,
      onOpen: onOpenGame,
      onTap: (gameId) => _activateLibraryGame(
        state: state,
        controller: controller,
        gameId: gameId,
        onOpen: onOpenGame,
      ),
      onToggleSelection: controller.toggleSelection,
      onForceRefresh: onForceRefresh,
    ),
  );
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.selected,
    required this.grid,
    required this.onOpen,
    required this.onTap,
    required this.onToggleSelection,
    required this.onForceRefresh,
  });

  final GameLibraryRow game;
  final bool selected;
  final bool grid;
  final void Function(GameId gameId) onOpen;
  final void Function(GameId gameId) onTap;
  final void Function(GameId gameId) onToggleSelection;
  final Future<void> Function(GameId gameId) onForceRefresh;

  @override
  Widget build(BuildContext context) {
    final content = grid
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _ArtworkPlaceholder(game: game)),
              const SizedBox(height: 10),
              Text(
                game.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${_platformShortLabel(game.platformId)} · ${_hydrationLabel(game.hydrationState)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )
        : Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: _ArtworkPlaceholder(game: game),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(_platformLabel(game.platformId)),
                    Text(
                      '${_hydrationLabel(game.hydrationState)} · ${_availabilityLabel(game.availabilityState)}',
                    ),
                  ],
                ),
              ),
            ],
          );
    return Card(
      key: ValueKey<String>('library-game-${game.gameId.value}'),
      clipBehavior: Clip.antiAlias,
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: Semantics(
        container: true,
        label: '${game.displayTitle}, ${_platformLabel(game.platformId)}',
        selected: selected,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.space) {
              onToggleSelection(game.gameId);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              onOpen(game.gameId);
              return KeyEventResult.handled;
            }
            final isForward =
                event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.arrowDown;
            final isBackward =
                event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowUp;
            if (isForward || isBackward) {
              final moved = isForward
                  ? FocusScope.of(context).nextFocus()
                  : FocusScope.of(context).previousFocus();
              return moved ? KeyEventResult.handled : KeyEventResult.ignored;
            }
            return KeyEventResult.ignored;
          },
          child: InkWell(
            onTap: () => onTap(game.gameId),
            onLongPress: () => onToggleSelection(game.gameId),
            child: Padding(
              padding: EdgeInsets.all(grid ? 12 : 10),
              child: grid
                  ? Stack(
                      children: [
                        Positioned.fill(child: content),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: Checkbox(
                            value: selected,
                            onChanged: (_) => onToggleSelection(game.gameId),
                          ),
                        ),
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: IconButton(
                            tooltip: 'Force refresh this Game',
                            onPressed: () =>
                                unawaited(onForceRefresh(game.gameId)),
                            icon: const Icon(Icons.restart_alt),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: content),
                        Checkbox(
                          value: selected,
                          onChanged: (_) => onToggleSelection(game.gameId),
                        ),
                        IconButton(
                          tooltip: 'Force refresh this Game',
                          onPressed: () =>
                              unawaited(onForceRefresh(game.gameId)),
                          icon: const Icon(Icons.restart_alt),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.game});

  final GameLibraryRow game;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Icon(
        game.selectedCoverAssetId == null
            ? Icons.videogame_asset_outlined
            : Icons.image_outlined,
        size: 34,
      ),
    ),
  );
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
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
          ),
        ),
      ),
    ),
  );
}

class _LibraryLoadFailure extends StatelessWidget {
  const _LibraryLoadFailure({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The Library could not be loaded.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => unawaited(onRetry()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _scopeTitle(LibraryScope scope) => switch (scope) {
  LibraryScopeAll() => 'Library',
  LibraryScopePlatform(:final platformId) => 'Library · $platformId',
  LibraryScopeSource(:final sourceId) => 'Library · Source $sourceId',
  LibraryScopeLibraryRoot(:final libraryRootId) =>
    'Library · Root $libraryRootId',
};

String _platformWire(PlatformId platform) => switch (platform) {
  PlatformId.nintendoNes => 'nintendo.nes',
  PlatformId.nintendoFds => 'nintendo.fds',
  PlatformId.nintendoSnes => 'nintendo.snes',
  PlatformId.nintendoGb => 'nintendo.gb',
  PlatformId.nintendoGbc => 'nintendo.gbc',
  PlatformId.nintendoGba => 'nintendo.gba',
  PlatformId.nintendoN64 => 'nintendo.n64',
  PlatformId.nintendoNds => 'nintendo.nds',
  PlatformId.nintendo3ds => 'nintendo.3ds',
  PlatformId.segaSms => 'sega.sms',
  PlatformId.segaGameGear => 'sega.gamegear',
  PlatformId.segaGenesis => 'sega.genesis',
  PlatformId.sega32x => 'sega.32x',
  PlatformId.nintendoGameCube => 'nintendo.gamecube',
  PlatformId.nintendoWii => 'nintendo.wii',
  PlatformId.segaCd => 'sega.sega-cd',
  PlatformId.segaSaturn => 'sega.saturn',
  PlatformId.segaDreamcast => 'sega.dreamcast',
  PlatformId.sonyPlaystation => 'sony.playstation',
  PlatformId.sonyPlaystation2 => 'sony.playstation2',
  PlatformId.sonyPsp => 'sony.psp',
};

String _platformShortLabel(PlatformId platform) => switch (platform) {
  PlatformId.nintendoNes => 'NES',
  PlatformId.nintendoFds => 'FDS',
  PlatformId.nintendoSnes => 'SNES',
  PlatformId.nintendoGb => 'Game Boy',
  PlatformId.nintendoGbc => 'Game Boy Color',
  PlatformId.nintendoGba => 'Game Boy Advance',
  PlatformId.nintendoN64 => 'N64',
  PlatformId.nintendoNds => 'Nintendo DS',
  PlatformId.nintendo3ds => 'Nintendo 3DS',
  PlatformId.segaSms => 'Master System',
  PlatformId.segaGameGear => 'Game Gear',
  PlatformId.segaGenesis => 'Genesis',
  PlatformId.sega32x => '32X',
  PlatformId.nintendoGameCube => 'GameCube',
  PlatformId.nintendoWii => 'Wii',
  PlatformId.segaCd => 'Sega CD',
  PlatformId.segaSaturn => 'Saturn',
  PlatformId.segaDreamcast => 'Dreamcast',
  PlatformId.sonyPlaystation => 'PlayStation',
  PlatformId.sonyPlaystation2 => 'PlayStation 2',
  PlatformId.sonyPsp => 'PSP',
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

String _availabilityLabel(AvailabilityState state) => switch (state) {
  AvailabilityState.available => 'Available',
  AvailabilityState.partiallyUnavailable => 'Partially unavailable',
  AvailabilityState.unavailable => 'Unavailable',
  AvailabilityState.inactiveOrphan => 'Inactive orphan',
};
