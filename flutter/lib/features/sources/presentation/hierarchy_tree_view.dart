import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/source_hierarchy_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sources_messages.dart';

/// Expanded/Large incremental tree over one shared hierarchy state model.
///
/// Only loaded scopes are rendered; expansion never triggers eager recursive
/// materialization. Keyboard navigation is complete: Up/Down move among
/// visible rows, Right expands/enters, Left collapses/returns to the parent,
/// Enter/Space activates the focused row.
class HierarchyTreeView extends StatefulWidget {
  const HierarchyTreeView({
    required this.state,
    required this.onExpand,
    required this.onCollapse,
    required this.onSelect,
    required this.onLoadMore,
    required this.onRetry,
    super.key,
  });

  final SourceHierarchyState state;
  final void Function(SourceEntry entry) onExpand;
  final void Function(SourceEntry entry) onCollapse;
  final void Function(SourceEntry entry) onSelect;
  final void Function(String parentKey) onLoadMore;
  final void Function(String parentKey) onRetry;

  @override
  State<HierarchyTreeView> createState() => _HierarchyTreeViewState();
}

sealed class _Row {
  const _Row(this.depth);

  final int depth;
}

final class _EntryRow extends _Row {
  const _EntryRow(this.entry, super.depth, this.parentKey);

  final SourceEntry entry;
  final String parentKey;
}

final class _FooterRow extends _Row {
  const _FooterRow(this.parentKey, super.depth);

  final String parentKey;
}

class _HierarchyTreeViewState extends State<HierarchyTreeView> {
  final Map<String, FocusNode> _focusNodes = {};
  late List<_Row> _rows = _flatten(widget.state);

  @override
  void didUpdateWidget(HierarchyTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rows = _flatten(widget.state);
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  List<_Row> _flatten(SourceHierarchyState state) {
    final rows = <_Row>[];
    void visit(String parentKey, int depth) {
      final scope = state.scopesByParent[parentKey];
      if (scope == null) return;
      for (final entry in scope.children) {
        rows.add(_EntryRow(entry, depth, parentKey));
        if (state.expandedEntryIds.contains(entry.sourceEntryId.value)) {
          visit(entry.sourceEntryId.value, depth + 1);
        }
      }
      if (scope.nextCursor != null || scope.failure != null) {
        rows.add(_FooterRow(parentKey, depth));
      }
    }

    visit('', 0);
    return rows;
  }

  String _rowKey(_Row row) => switch (row) {
    _EntryRow(:final entry) => 'entry-${entry.sourceEntryId.value}',
    _FooterRow(:final parentKey) => 'footer-$parentKey',
  };

  FocusNode _nodeFor(_Row row) =>
      _focusNodes.putIfAbsent(_rowKey(row), FocusNode.new);

  KeyEventResult _onKey(_Row row, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final index = _rows.indexOf(row);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _focusRelative(index, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _focusRelative(index, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (row case _EntryRow(:final entry)) {
          final expanded = widget.state.expandedEntryIds.contains(
            entry.sourceEntryId.value,
          );
          final traversable =
              entry.kind == SourceEntryKind.directory &&
              entry.classification == SourceEntryClassification.container;
          if (traversable && !expanded) {
            widget.onExpand(entry);
            return KeyEventResult.handled;
          }
          if (traversable && expanded) {
            _EntryRow? firstChild;
            for (var i = index + 1; i < _rows.length; i++) {
              final candidate = _rows[i];
              if (candidate is _EntryRow &&
                  candidate.parentKey == entry.sourceEntryId.value) {
                firstChild = candidate;
                break;
              }
              if (candidate.depth <= row.depth) break;
            }
            if (firstChild != null) {
              _focusRow(firstChild);
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        if (row case _EntryRow(:final entry)) {
          final expanded = widget.state.expandedEntryIds.contains(
            entry.sourceEntryId.value,
          );
          if (expanded) {
            widget.onCollapse(entry);
            return KeyEventResult.handled;
          }
          _EntryRow? parent;
          for (var i = index - 1; i >= 0; i--) {
            final candidate = _rows[i];
            if (candidate is _EntryRow && candidate.depth == row.depth - 1) {
              parent = candidate;
              break;
            }
          }
          if (parent != null) {
            _focusRow(parent);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        if (row case _EntryRow(:final entry)) {
          widget.onSelect(entry);
        } else if (row case _FooterRow(:final parentKey)) {
          final scope = widget.state.scopesByParent[parentKey];
          if (scope?.failure != null) {
            widget.onRetry(parentKey);
          } else if (scope?.nextCursor != null) {
            widget.onLoadMore(parentKey);
          }
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _focusRelative(int index, int delta) {
    final target = index + delta;
    if (target >= 0 && target < _rows.length) {
      _focusRow(_rows[target]);
    }
  }

  void _focusRow(_Row row) {
    _nodeFor(row).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return const Center(child: Text(SourcesMessages.hierarchyEmpty));
    }
    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (context, index) {
        final row = _rows[index];
        final node = _nodeFor(row);
        return Focus(
          key: ValueKey<String>('focus-${_rowKey(row)}'),
          focusNode: node,
          onKeyEvent: (node, event) => _onKey(row, node, event),
          child: switch (row) {
            _EntryRow(:final entry, :final depth) => _buildEntryRow(
              entry,
              depth,
            ),
            _FooterRow(:final parentKey, :final depth) => _buildFooterRow(
              parentKey,
              depth,
            ),
          },
        );
      },
    );
  }

  Widget _buildEntryRow(SourceEntry entry, int depth) {
    final expanded = widget.state.expandedEntryIds.contains(
      entry.sourceEntryId.value,
    );
    final selected = widget.state.selectedEntryId == entry.sourceEntryId;
    final traversable =
        entry.kind == SourceEntryKind.directory &&
        entry.classification == SourceEntryClassification.container;
    return Semantics(
      expanded: traversable ? expanded : null,
      selected: selected,
      child: ListTile(
        key: ValueKey<String>('hierarchy-row-${entry.sourceEntryId.value}'),
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 16),
        leading: Icon(
          traversable
              ? (expanded ? Icons.folder_open_outlined : Icons.folder_outlined)
              : Icons.insert_drive_file_outlined,
        ),
        title: Text(entry.displayName),
        subtitle: Text(
          '${SourcesMessages.entryKindLabel(entry.kind)} · '
          '${SourcesMessages.entryClassificationLabel(entry.classification)}',
        ),
        trailing: selected
            ? const Icon(Icons.check)
            : traversable
            ? Icon(expanded ? Icons.expand_more : Icons.chevron_right)
            : null,
        selected: selected,
        onTap: () {
          widget.onSelect(entry);
          if (traversable) {
            if (expanded) {
              widget.onCollapse(entry);
            } else {
              widget.onExpand(entry);
            }
          }
        },
      ),
    );
  }

  Widget _buildFooterRow(String parentKey, int depth) {
    final scope = widget.state.scopesByParent[parentKey];
    final failed = scope?.failure != null;
    return Padding(
      padding: EdgeInsets.only(left: 40.0 + depth * 20, right: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              failed
                  ? SourcesMessages.hierarchyRefreshFailed
                  : scope?.loadingMore == true
                  ? SourcesMessages.hierarchyLoading
                  : SourcesMessages.loadMore,
            ),
          ),
          TextButton(
            key: ValueKey<String>('hierarchy-footer-$parentKey'),
            onPressed: failed
                ? () => widget.onRetry(parentKey)
                : () => widget.onLoadMore(parentKey),
            child: Text(
              failed ? SourcesMessages.retry : SourcesMessages.loadMore,
            ),
          ),
        ],
      ),
    );
  }
}
