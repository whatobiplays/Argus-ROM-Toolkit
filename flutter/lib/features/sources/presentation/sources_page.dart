import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/add_library_folder_controller.dart';
import 'package:argus/features/sources/application/root_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_library_folder_flow.dart';
import 'sources_messages.dart';

/// The Sources landing: empty state or the configured-root list.
///
/// Presentation only: navigation is callback-driven and all displayed state
/// comes from focused authoritative reads.
class SourcesPage extends ConsumerWidget {
  const SourcesPage({required this.onOpenRoot, super.key});

  /// Opens one configured root's detail location.
  final void Function(LibraryRootId rootId) onOpenRoot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(sourcesRootListControllerProvider);
    final addState = ref.watch(sourcesAddLibraryFolderControllerProvider);
    final adding = addState is SourcesAddOperationSubmitting;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sources',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton.icon(
                    key: const ValueKey<String>('sources-add-library-folder'),
                    onPressed: adding
                        ? null
                        : () => runAddLibraryFolderFlow(
                            context,
                            ref,
                            onOpenRoot: onOpenRoot,
                            onNotice: (message) =>
                                _showNotice(context, message),
                          ),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text(SourcesMessages.addLibraryFolder),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildList(context, ref, listState)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<SourcesRootListState> listState,
  ) {
    return listState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _InitialLoadFailure(
        onRetry: () =>
            ref.read(sourcesRootListControllerProvider.notifier).refresh(),
      ),
      data: (state) {
        final ready = state as SourcesRootListStateReady;
        if (ready.totalCount == 0) {
          return const _EmptyState();
        }
        final itemCount = ready.hasMore
            ? ready.roots.length + 1
            : ready.roots.length;
        return ListView.separated(
          key: const ValueKey<String>('sources-root-list'),
          itemCount: itemCount,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index >= ready.roots.length) {
              return _LoadMoreRow(
                loading: ready.loadingMore,
                failed: ready.loadMoreFailed,
                onLoadMore: () => ref
                    .read(sourcesRootListControllerProvider.notifier)
                    .loadMore(),
              );
            }
            final root = ready.roots[index];
            return ListTile(
              key: ValueKey<String>('sources-root-${root.id.value}'),
              leading: const Icon(Icons.folder_outlined),
              title: Text(root.displayName),
              subtitle: Text(root.safeLocationPresentation),
              trailing: Text(SourcesMessages.neverScanned),
              onTap: () => onOpenRoot(root.id),
            );
          },
        );
      },
    );
  }

  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
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
        key: ValueKey<String>('sources-loading-more'),
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Loading more folders…'),
      );
    }
    if (failed) {
      return ListTile(
        key: const ValueKey<String>('sources-load-more-retry'),
        title: const Text('Could not load more folders'),
        trailing: TextButton(onPressed: onLoadMore, child: const Text('Retry')),
      );
    }
    return ListTile(
      key: const ValueKey<String>('sources-load-more'),
      title: const Text('Load more folders'),
      trailing: const Icon(Icons.expand_more),
      onTap: onLoadMore,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              SourcesMessages.emptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(SourcesMessages.emptyBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _InitialLoadFailure extends StatelessWidget {
  const _InitialLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(SourcesMessages.loadFailed),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text(SourcesMessages.retry),
          ),
        ],
      ),
    );
  }
}
