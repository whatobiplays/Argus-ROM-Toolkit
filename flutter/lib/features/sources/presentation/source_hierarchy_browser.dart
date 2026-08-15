import 'package:argus/core/client/client.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:argus/features/sources/application/source_hierarchy_controller.dart';
import 'package:argus/features/sources/application/source_hierarchy_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hierarchy_drill_down_view.dart';
import 'hierarchy_tree_view.dart';
import 'source_entry_inspector.dart';
import 'sources_messages.dart';

/// Adaptive hierarchy browser for root detail.
///
/// Compact/Medium use drill-down; Expanded/Large use an incremental tree. All
/// presentations share one controller/state model, and selection is transient
/// feature state, never route state.
class SourceHierarchyBrowser extends ConsumerStatefulWidget {
  const SourceHierarchyBrowser({required this.rootId, super.key});

  final LibraryRootId rootId;

  @override
  ConsumerState<SourceHierarchyBrowser> createState() =>
      _SourceHierarchyBrowserState();
}

class _SourceHierarchyBrowserState
    extends ConsumerState<SourceHierarchyBrowser> {
  final GlobalKey<HierarchyDrillDownViewState> _drillDownKey =
      GlobalKey<HierarchyDrillDownViewState>();

  LibraryRootId get rootId => widget.rootId;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final hierarchy = ref.watch(sourceHierarchyControllerProvider(rootId));
    final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);
    final useDrillDown =
        sizeClass == WindowSizeClass.compact ||
        sizeClass == WindowSizeClass.medium;
    return hierarchy.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SourcesMessages.hierarchyLoadFailed),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey<String>('hierarchy-initial-retry'),
              onPressed: () => ref
                  .read(sourceHierarchyControllerProvider(rootId).notifier)
                  .refresh(rootId),
              child: const Text(SourcesMessages.retry),
            ),
          ],
        ),
      ),
      data: (state) => LayoutBuilder(
        builder: (context, constraints) {
          // Local-width adaptation reuses the canonical responsive
          // classification so breakpoint literals stay single-sourced.
          final localClass = classifyWindowWidth(constraints.maxWidth);
          final narrowInspector = localClass == WindowSizeClass.compact;
          final selected = state.selectedEntryId;
          if (useDrillDown) {
            return Column(
              children: [
                Expanded(
                  child: HierarchyDrillDownView(
                    key: _drillDownKey,
                    state: state,
                    onOpenEntry: (entry) => ref
                        .read(
                          sourceHierarchyControllerProvider(rootId).notifier,
                        )
                        .openContainer(rootId, entry.sourceEntryId),
                    onSelectEntry: (entry) {
                      ref
                          .read(
                            sourceHierarchyControllerProvider(rootId).notifier,
                          )
                          .select(rootId, entry.sourceEntryId);
                      if (narrowInspector) {
                        _showTransientInspector(context, entry.sourceEntryId);
                      }
                    },
                    onBack: () => ref
                        .read(
                          sourceHierarchyControllerProvider(rootId).notifier,
                        )
                        .goBack(rootId),
                    onLoadMore: () => ref
                        .read(
                          sourceHierarchyControllerProvider(rootId).notifier,
                        )
                        .loadMore(rootId, _currentScopeKey(state)),
                    onRetry: () => ref
                        .read(
                          sourceHierarchyControllerProvider(rootId).notifier,
                        )
                        .retry(rootId, _currentScopeKey(state)),
                  ),
                ),
                if (!narrowInspector && selected != null)
                  SizedBox(
                    height: 280,
                    child: SourceEntryInspector(
                      rootId: rootId,
                      entryId: selected,
                    ),
                  ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: HierarchyTreeView(
                  state: state,
                  onExpand: (entry) => ref
                      .read(sourceHierarchyControllerProvider(rootId).notifier)
                      .expand(rootId, entry.sourceEntryId),
                  onCollapse: (entry) => ref
                      .read(sourceHierarchyControllerProvider(rootId).notifier)
                      .collapse(rootId, entry.sourceEntryId),
                  onSelect: (entry) => ref
                      .read(sourceHierarchyControllerProvider(rootId).notifier)
                      .select(rootId, entry.sourceEntryId),
                  onLoadMore: (parentKey) => ref
                      .read(sourceHierarchyControllerProvider(rootId).notifier)
                      .loadMore(rootId, parentKey),
                  onRetry: (parentKey) => ref
                      .read(sourceHierarchyControllerProvider(rootId).notifier)
                      .retry(rootId, parentKey),
                ),
              ),
              if (selected != null)
                SizedBox(
                  width: 300,
                  child: SourceEntryInspector(
                    rootId: rootId,
                    entryId: selected,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _currentScopeKey(SourceHierarchyState state) =>
      state.compactDrillDownPath.isEmpty
      ? ''
      : state.compactDrillDownPath.last.value;

  Future<void> _showTransientInspector(
    BuildContext context,
    SourceEntryId entryId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          SourceEntryInspector(rootId: rootId, entryId: entryId),
    );
    if (mounted) {
      _drillDownKey.currentState?.focusEntry(entryId);
    }
  }
}
