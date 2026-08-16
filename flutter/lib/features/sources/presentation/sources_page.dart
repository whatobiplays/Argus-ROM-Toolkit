import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/add_library_folder_controller.dart';
import 'package:argus/features/sources/application/root_list_controller.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_library_folder_flow.dart';
import 'sources_messages.dart';

/// The Sources landing: empty state or the configured-root list.
///
/// Presentation only: navigation is callback-driven and all displayed state
/// comes from focused authoritative reads.
class SourcesPage extends ConsumerWidget {
  const SourcesPage({
    required this.onOpenRoot,
    required this.onOpenJob,
    super.key,
  });

  /// Opens one configured root's detail location.
  final void Function(LibraryRootId rootId) onOpenRoot;

  /// Opens one durable job detail through the typed Jobs route.
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(sourcesRootListControllerProvider);
    final addState = ref.watch(sourcesAddLibraryFolderControllerProvider);
    final adding = addState is SourcesAddOperationSubmitting;
    final capabilities = ref.watch(sourcesPresentationCapabilitiesProvider);
    final ready = listState.value;
    final canScanAll =
        capabilities.scanAllExecution &&
        ready is SourcesRootListStateReady &&
        ready.totalCount > 0;
    final scanAllBlocked =
        ready is SourcesRootListStateReady &&
        (ready.scanAllStatus is SourcesScanAllStatusSubmitting ||
            ready.scanAllStatus is SourcesScanAllStatusUncertain);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Sources',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (canScanAll) ...[
                    OutlinedButton.icon(
                      key: const ValueKey<String>('sources-scan-all'),
                      onPressed: scanAllBlocked
                          ? null
                          : () => ref
                                .read(
                                  sourcesRootListControllerProvider.notifier,
                                )
                                .startScanAll(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(SourcesMessages.scanAll),
                    ),
                    const SizedBox(width: 8),
                  ],
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
              if (ready is SourcesRootListStateReady)
                _ScanAllFeedback(
                  status: ready.scanAllStatus,
                  onViewJob: (jobRunId) => onOpenJob(jobRunId),
                ),
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
              trailing: Text(
                root.activeScan != null
                    ? SourcesMessages.scanningInProgress
                    : root.lastScan != null
                    ? SourcesMessages.lastScanStatus(root.lastScan!.status)
                    : SourcesMessages.neverScanned,
              ),
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

class _ScanAllFeedback extends StatelessWidget {
  const _ScanAllFeedback({required this.status, required this.onViewJob});

  final SourcesScanAllStatus status;
  final void Function(JobRunId jobRunId) onViewJob;

  @override
  Widget build(BuildContext context) {
    final Widget? content = switch (status) {
      SourcesScanAllStatusIdle() || SourcesScanAllStatusSubmitting() => null,
      SourcesScanAllStatusAdmitted(
        :final admittedCount,
        :final hasExclusions,
        :final jobRunId,
      ) =>
        Row(
          children: [
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasExclusions
                    ? SourcesMessages.scanAllAdmittedWithExclusions(
                        admittedCount,
                      )
                    : SourcesMessages.scanAllAdmitted(admittedCount),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('sources-scan-all-view-job'),
              onPressed: () => onViewJob(jobRunId),
              child: const Text(SourcesMessages.viewJob),
            ),
          ],
        ),
      SourcesScanAllStatusNothingEligible(:final exclusions) => Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              exclusions.isEmpty
                  ? SourcesMessages.scanAllNothingEligible
                  : SourcesMessages.scanAllNothingEligibleReasons([
                      for (final exclusion in exclusions)
                        SourcesMessages.scanAllExclusionLabel(exclusion),
                    ]),
            ),
          ),
        ],
      ),
      SourcesScanAllStatusUncertain() => const Row(
        children: [
          Icon(Icons.sync_problem),
          SizedBox(width: 8),
          Expanded(child: Text(SourcesMessages.scanAllUncertain)),
        ],
      ),
    };
    if (content == null) {
      return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: content);
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
