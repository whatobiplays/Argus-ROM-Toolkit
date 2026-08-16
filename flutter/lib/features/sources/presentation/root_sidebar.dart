import 'package:argus/core/client/client.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:argus/features/sources/application/root_list_controller.dart';
import 'package:argus/features/sources/application/sources_session_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sources-local configured-root sidebar used on Expanded/Large layouts.
///
/// The collapse preference is session-only: adaptive defaults apply while the
/// override is `none`, an explicit choice wins for the remainder of the
/// Flutter application/provider scope, and a fresh scope resets to `none`.
class SourcesRootSidebar extends ConsumerWidget {
  const SourcesRootSidebar({
    required this.selectedRootId,
    required this.onOpenRoot,
    super.key,
  });

  final LibraryRootId selectedRootId;
  final void Function(LibraryRootId rootId) onOpenRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(sourcesRootListControllerProvider);
    final preference = ref.watch(sourcesSidebarPreferenceProvider);
    final ready = listState.value;
    final totalCount = ready?.totalCount ?? 0;
    if (totalCount == 0) {
      return const SizedBox.shrink();
    }
    final collapsed = switch (preference) {
      SourcesSidebarOverride.none => totalCount <= 1,
      SourcesSidebarOverride.collapsed => true,
      SourcesSidebarOverride.expanded => false,
    };
    final readyState = ready is SourcesRootListStateReady ? ready : null;

    // The sidebar switches width instantly rather than animating: an
    // animated 64 -> 240 transition lays out expanded ListTiles at
    // intermediate widths where their leading icon plus padding exceed the
    // tile width, which trips a ListTile layout assertion. Collapse/expand
    // remains a session preference; only the decorative width animation is
    // omitted.
    return SizedBox(
      width: collapsed ? 64 : 240,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SafeArea(
          child: collapsed
              ? _CollapsedSidebar(
                  totalCount: totalCount,
                  onExpand: () => ref
                      .read(sourcesSidebarPreferenceProvider.notifier)
                      .expand(),
                )
              : _ExpandedSidebar(
                  roots: readyState?.roots ?? const [],
                  hasMore: readyState?.hasMore ?? false,
                  loadingMore: readyState?.loadingMore ?? false,
                  loadMoreFailed: readyState?.loadMoreFailed ?? false,
                  selectedRootId: selectedRootId,
                  onOpenRoot: onOpenRoot,
                  onLoadMore: () => ref
                      .read(sourcesRootListControllerProvider.notifier)
                      .loadMore(),
                  onCollapse: () => ref
                      .read(sourcesSidebarPreferenceProvider.notifier)
                      .collapse(),
                ),
        ),
      ),
    );
  }
}

class _CollapsedSidebar extends StatelessWidget {
  const _CollapsedSidebar({required this.totalCount, required this.onExpand});

  final int totalCount;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        IconButton(
          key: const ValueKey<String>('sources-sidebar-expand'),
          tooltip: 'Expand library folders',
          onPressed: onExpand,
          icon: const Icon(Icons.folder_outlined),
        ),
        Text('$totalCount', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    required this.roots,
    required this.hasMore,
    required this.loadingMore,
    required this.loadMoreFailed,
    required this.selectedRootId,
    required this.onOpenRoot,
    required this.onLoadMore,
    required this.onCollapse,
  });

  final List<LibraryRoot> roots;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
  final LibraryRootId selectedRootId;
  final void Function(LibraryRootId rootId) onOpenRoot;
  final VoidCallback onLoadMore;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Library folders',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                key: const ValueKey<String>('sources-sidebar-collapse'),
                tooltip: 'Collapse library folders',
                onPressed: onCollapse,
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            key: const ValueKey<String>('sources-sidebar-list'),
            itemCount: roots.length,
            itemBuilder: (context, index) {
              final root = roots[index];
              final selected = root.id == selectedRootId;
              return ListTile(
                key: ValueKey<String>('sources-sidebar-${root.id.value}'),
                selected: selected,
                leading: const Icon(Icons.folder_outlined),
                title: Text(root.displayName),
                subtitle: Text(root.safeLocationPresentation),
                onTap: () => onOpenRoot(root.id),
              );
            },
          ),
        ),
        if (hasMore) ...[
          const Divider(height: 1),
          _SidebarLoadMoreRow(
            loading: loadingMore,
            failed: loadMoreFailed,
            onLoadMore: onLoadMore,
          ),
        ],
      ],
    );
  }
}

class _SidebarLoadMoreRow extends StatelessWidget {
  const _SidebarLoadMoreRow({
    required this.loading,
    required this.failed,
    required this.onLoadMore,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const ListTile(
        key: ValueKey<String>('sources-sidebar-loading-more'),
        dense: true,
        leading: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Loading more folders…'),
      );
    }
    if (failed) {
      return ListTile(
        key: const ValueKey<String>('sources-sidebar-load-more-retry'),
        dense: true,
        title: const Text('Could not load more folders'),
        onTap: onLoadMore,
        trailing: TextButton(onPressed: onLoadMore, child: const Text('Retry')),
      );
    }
    return ListTile(
      key: const ValueKey<String>('sources-sidebar-load-more'),
      dense: true,
      leading: const Icon(Icons.expand_more),
      title: const Text('Load more folders'),
      onTap: onLoadMore,
    );
  }
}

/// Whether the current window size class uses the list/detail split.
bool sourcesUsesSidebarLayout(BuildContext context) {
  final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);
  return sizeClass == WindowSizeClass.expanded ||
      sizeClass == WindowSizeClass.large;
}
