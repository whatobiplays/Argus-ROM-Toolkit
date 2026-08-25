import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/application/jobs_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jobs_messages.dart';

/// The Jobs landing: Active then Recent, both query-authoritative.
class JobsPage extends ConsumerWidget {
  const JobsPage({required this.onOpenJob, super.key});

  /// Opens one durable execution attempt through the typed route.
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(jobsListControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                JobsMessages.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: listState.when(
                  loading: () => Center(
                    child: Semantics(
                      liveRegion: true,
                      label: 'Loading jobs',
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, stackTrace) => _LoadFailure(
                    onRetry: () =>
                        ref.read(jobsListControllerProvider.notifier).refresh(),
                  ),
                  data: (state) => _JobsContent(
                    state: state as JobsListStateReady,
                    onOpenJob: onOpenJob,
                    onLoadMore: () => ref
                        .read(jobsListControllerProvider.notifier)
                        .loadMore(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobsContent extends StatelessWidget {
  const _JobsContent({
    required this.state,
    required this.onOpenJob,
    required this.onLoadMore,
  });

  final JobsListStateReady state;
  final void Function(JobRunId jobRunId) onOpenJob;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.activeJobs.isEmpty && state.recentJobs.isEmpty) {
      return const _EmptyState();
    }
    return ListView(
      key: const ValueKey<String>('jobs-list'),
      children: [
        if (state.activeJobs.isNotEmpty) ...[
          Semantics(
            header: true,
            child: Text(
              JobsMessages.active,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final job in state.activeJobs)
            _JobRow(job: job, onOpenJob: onOpenJob),
          const SizedBox(height: 16),
        ],
        if (state.recentJobs.isNotEmpty) ...[
          Semantics(
            header: true,
            child: Text(
              JobsMessages.recent,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final job in state.recentJobs)
            _JobRow(job: job, onOpenJob: onOpenJob),
        ],
        if (state.nextOffset != null) ...[
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey<String>('jobs-load-more'),
            title: Text(
              state.loadMoreFailed
                  ? '${JobsMessages.loadMore} (failed)'
                  : JobsMessages.loadMore,
            ),
            trailing: state.loadingMore
                ? Semantics(
                    liveRegion: true,
                    label: 'Loading more jobs',
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.expand_more),
            onTap: state.loadingMore ? null : onLoadMore,
          ),
        ],
      ],
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.onOpenJob});

  final JobListItem job;
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  Widget build(BuildContext context) {
    final label = _operationLabel(job.operationType);
    final stateLabel = _lifecycleLabel(job.lifecycleState);
    return ListTile(
      key: ValueKey<String>('jobs-row-${job.jobRunId.value}'),
      leading: Icon(
        job.lifecycleState.isTerminal ? Icons.check_circle_outline : Icons.sync,
      ),
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        job.cancellationRequested && !job.lifecycleState.isTerminal
            ? '$stateLabel (cancelling)'
            : stateLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: false,
      onTap: () => onOpenJob(job.jobRunId),
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
            const Icon(Icons.receipt_long_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              JobsMessages.emptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(JobsMessages.emptyBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            label: JobsMessages.loadFailed,
            child: Text(JobsMessages.loadFailed),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text(JobsMessages.retry),
          ),
        ],
      ),
    );
  }
}

String _operationLabel(String operationType) => switch (operationType) {
  'library_scan' => JobsMessages.libraryScan,
  'library_refresh' => JobsMessages.libraryRefresh,
  'game_refresh' => JobsMessages.gameRefresh,
  'library_resolution_refresh' => JobsMessages.libraryResolutionRefresh,
  _ => operationType,
};

String _lifecycleLabel(JobLifecycleState state) => switch (state) {
  JobLifecycleState.queued => 'Queued',
  JobLifecycleState.preparing => 'Preparing',
  JobLifecycleState.running => 'Running',
  JobLifecycleState.completed => 'Completed',
  JobLifecycleState.completedWithIssues => 'Completed with issues',
  JobLifecycleState.failed => 'Failed',
  JobLifecycleState.cancelled => 'Cancelled',
  JobLifecycleState.interrupted => 'Interrupted',
  JobLifecycleState.abandoned => 'Abandoned',
};
