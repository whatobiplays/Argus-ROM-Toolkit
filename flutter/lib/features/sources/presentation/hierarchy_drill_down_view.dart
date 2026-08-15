import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/source_hierarchy_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sources_messages.dart';

/// Compact/Medium drill-down browser over one shared hierarchy state model.
class HierarchyDrillDownView extends StatefulWidget {
  const HierarchyDrillDownView({
    required this.state,
    required this.onOpenEntry,
    required this.onSelectEntry,
    required this.onBack,
    required this.onLoadMore,
    required this.onRetry,
    super.key,
  });

  final SourceHierarchyState state;
  final void Function(SourceEntry entry) onOpenEntry;
  final void Function(SourceEntry entry) onSelectEntry;
  final VoidCallback onBack;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  State<HierarchyDrillDownView> createState() => HierarchyDrillDownViewState();
}

class HierarchyDrillDownViewState extends State<HierarchyDrillDownView> {
  final Map<String, FocusNode> _focusNodes = {};

  String get _currentScopeKey => widget.state.compactDrillDownPath.isEmpty
      ? ''
      : widget.state.compactDrillDownPath.last.value;

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Restores keyboard focus to one entry row after a transient surface
  /// closes, when that row still exists.
  void focusEntry(SourceEntryId entryId) {
    final node = _focusNodes[entryId.value];
    if (node != null) {
      node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final scope = state.scopesByParent[_currentScopeKey];
    final entries = scope?.children ?? const <SourceEntry>[];
    final currentLabel = _currentLabel();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              key: const ValueKey<String>('hierarchy-back'),
              onPressed: state.compactDrillDownPath.isEmpty
                  ? null
                  : widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text(SourcesMessages.back),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                currentLabel,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text(SourcesMessages.hierarchyEmpty))
              : ListView.separated(
                  itemCount: entries.length + _footerCount(scope),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index < entries.length) {
                      final entry = entries[index];
                      final traversable =
                          entry.kind == SourceEntryKind.directory &&
                          entry.classification ==
                              SourceEntryClassification.container;
                      return Focus(
                        key: ValueKey<String>(
                          'focus-hierarchy-${entry.sourceEntryId.value}',
                        ),
                        focusNode: _focusNodes.putIfAbsent(
                          entry.sourceEntryId.value,
                          FocusNode.new,
                        ),
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              (event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.space)) {
                            traversable
                                ? widget.onOpenEntry(entry)
                                : widget.onSelectEntry(entry);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Semantics(
                          selected:
                              state.selectedEntryId == entry.sourceEntryId,
                          child: ListTile(
                            key: ValueKey<String>(
                              'hierarchy-row-${entry.sourceEntryId.value}',
                            ),
                            leading: Icon(
                              traversable
                                  ? Icons.folder_outlined
                                  : Icons.insert_drive_file_outlined,
                            ),
                            title: Text(entry.displayName),
                            subtitle: Text(
                              '${SourcesMessages.entryKindLabel(entry.kind)} · '
                              '${SourcesMessages.entryClassificationLabel(entry.classification)}',
                            ),
                            trailing: traversable
                                ? const Icon(Icons.chevron_right)
                                : state.selectedEntryId == entry.sourceEntryId
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => traversable
                                ? widget.onOpenEntry(entry)
                                : widget.onSelectEntry(entry),
                          ),
                        ),
                      );
                    }
                    return _buildFooter(scope);
                  },
                ),
        ),
      ],
    );
  }

  String _currentLabel() {
    final state = widget.state;
    if (state.compactDrillDownPath.isEmpty) {
      return SourcesMessages.libraryRootLevel;
    }
    final currentId = state.compactDrillDownPath.last;
    for (final scope in state.scopesByParent.values) {
      for (final entry in scope.children) {
        if (entry.sourceEntryId == currentId) {
          return entry.displayName;
        }
      }
    }
    return SourcesMessages.libraryRootLevel;
  }

  int _footerCount(ParentScopeState? scope) {
    if (scope == null || !scope.hasLoaded) return 0;
    if (scope.nextCursor != null || scope.failure != null) return 1;
    return 0;
  }

  Widget _buildFooter(ParentScopeState? scope) {
    if (scope == null || !scope.hasLoaded) {
      return const SizedBox.shrink();
    }
    if (scope.failure != null) {
      return ListTile(
        key: const ValueKey<String>('hierarchy-scope-retry'),
        title: const Text(SourcesMessages.hierarchyRefreshFailed),
        trailing: TextButton(
          onPressed: widget.onRetry,
          child: const Text(SourcesMessages.retry),
        ),
      );
    }
    if (scope.nextCursor != null) {
      return ListTile(
        key: const ValueKey<String>('hierarchy-load-more'),
        title: Text(
          scope.loadingMore
              ? SourcesMessages.hierarchyLoading
              : SourcesMessages.loadMore,
        ),
        trailing: scope.loadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: widget.onLoadMore,
                child: const Text(SourcesMessages.loadMore),
              ),
      );
    }
    return const SizedBox.shrink();
  }
}
