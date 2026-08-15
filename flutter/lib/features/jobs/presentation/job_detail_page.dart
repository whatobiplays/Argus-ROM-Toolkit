import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/application/job_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jobs_messages.dart';

/// One durable execution attempt's detail surface.
class JobDetailPage extends ConsumerWidget {
  const JobDetailPage({
    required this.jobRunId,
    required this.onMissingJob,
    required this.onOpenJob,
    super.key,
  });

  final JobRunId jobRunId;

  /// Canonicalizes to /jobs when the job cannot be resolved authoritatively.
  final VoidCallback onMissingJob;

  /// Opens another execution identity (retry source/successor navigation).
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailState = ref.watch(jobDetailControllerProvider(jobRunId));
    ref.listen(jobDetailControllerProvider(jobRunId), (previous, next) {
      if (next.value is JobDetailStateMissing) {
        onMissingJob();
      }
    });
    final content = detailState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(JobsMessages.loadFailed),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref
                    .read(jobDetailControllerProvider(jobRunId).notifier)
                    .refresh(jobRunId),
                child: const Text(JobsMessages.retry),
              ),
            ],
          ),
        ),
      ),
      data: (state) => switch (state) {
        JobDetailStateMissing() => const SizedBox.shrink(),
        JobDetailStateReady(
          :final detail,
          :final refreshing,
          :final cancelling,
          :final cancelAmbiguous,
          :final retrying,
          :final retryAmbiguous,
          :final retryNotAdmittedReason,
          :final lastFailure,
        ) =>
          _JobDetailContent(
            detail: detail,
            refreshing: refreshing,
            cancelling: cancelling,
            cancelAmbiguous: cancelAmbiguous,
            retrying: retrying,
            retryAmbiguous: retryAmbiguous,
            retryNotAdmittedReason: retryNotAdmittedReason,
            lastFailure: lastFailure,
            onCancel: () => ref
                .read(jobDetailControllerProvider(jobRunId).notifier)
                .cancel(jobRunId),
            onRetry: () => ref
                .read(jobDetailControllerProvider(jobRunId).notifier)
                .retry(
                  jobRunId,
                  onAdmitted: (newJobRunId) => onOpenJob(newJobRunId),
                ),
            onOpenJob: onOpenJob,
          ),
      },
    );
    return content;
  }
}

class _JobDetailContent extends StatelessWidget {
  const _JobDetailContent({
    required this.detail,
    required this.refreshing,
    required this.cancelling,
    required this.cancelAmbiguous,
    required this.retrying,
    required this.retryAmbiguous,
    required this.retryNotAdmittedReason,
    required this.lastFailure,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenJob,
  });

  final JobDetail detail;
  final bool refreshing;
  final bool cancelling;
  final bool cancelAmbiguous;
  final bool retrying;
  final bool retryAmbiguous;
  final RetryNotAdmittedReason? retryNotAdmittedReason;
  final ClientFailure? lastFailure;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final void Function(JobRunId jobRunId) onOpenJob;

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(JobsMessages.cancelConfirmationTitle),
        content: const Text(JobsMessages.cancelConfirmationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(JobsMessages.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(JobsMessages.cancelJob),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      onCancel();
    }
  }

  Future<void> _confirmRetry(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(JobsMessages.retryConfirmationTitle),
        content: const Text(JobsMessages.retryConfirmationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(JobsMessages.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(JobsMessages.retryJob),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      onRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = detail.job;
    final scanDetail = switch (detail.operationDetail) {
      OperationDetailLibraryScan(:final detail) => detail,
    };
    final controls = job.controls;
    final controlsBusy = cancelling || retrying;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      JobsMessages.libraryScan,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (controls.canCancel && !controlsBusy && !retryAmbiguous)
                    OutlinedButton.icon(
                      key: const ValueKey<String>('jobs-cancel-job'),
                      onPressed: () => _confirmCancel(context),
                      icon: const Icon(Icons.close),
                      label: const Text(JobsMessages.cancelJob),
                    ),
                  if (controls.canRetry &&
                      !controlsBusy &&
                      !cancelAmbiguous &&
                      !retryAmbiguous)
                    const SizedBox(width: 8),
                  if (controls.canRetry && !controlsBusy && !retryAmbiguous)
                    FilledButton.icon(
                      key: const ValueKey<String>('jobs-retry-job'),
                      onPressed: () => _confirmRetry(context),
                      icon: const Icon(Icons.refresh),
                      label: const Text(JobsMessages.retryJob),
                    ),
                  if (controlsBusy)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_lifecycleLabel(job.lifecycleState)),
              if (job.phase != null) ...[
                const SizedBox(height: 8),
                Text('${JobsMessages.phase}: ${job.phase}'),
              ],
              const SizedBox(height: 8),
              Text('${JobsMessages.created}: ${_time(job.createdAtMs)}'),
              if (job.startedAtMs != null)
                Text('${JobsMessages.started}: ${_time(job.startedAtMs!)}'),
              if (job.terminalAtMs != null)
                Text('${JobsMessages.finished}: ${_time(job.terminalAtMs!)}'),
              if (job.cancellationRequested && !job.lifecycleState.isTerminal)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(JobsMessages.cancelling),
                ),
              if (cancelAmbiguous)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cancellation could not be confirmed. '
                    'Refreshing authoritative state.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (retryAmbiguous)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    JobsMessages.retryUncertain,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (retryNotAdmittedReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_retryReasonLabel(retryNotAdmittedReason!)),
                ),
              if (lastFailure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Could not refresh this job.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const Divider(height: 32),
              _ProgressFacts(progress: scanDetail.progress),
              const SizedBox(height: 16),
              if (scanDetail.requestedRoots.isNotEmpty) ...[
                Text(
                  'Requested folders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final root in scanDetail.requestedRoots)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(root.displayName),
                    subtitle: Text(root.safeLocationDisplay),
                  ),
              ],
              if (scanDetail.exclusions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Excluded',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final exclusion in scanDetail.exclusions)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.block),
                    title: Text(exclusion.reason),
                  ),
              ],
              for (final scan in scanDetail.scanRuns)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(scan.displayName),
                  subtitle: Text(_scanStatusLabel(scan.status)),
                ),
              if (scanDetail.retrySourceJobRunId != null ||
                  scanDetail.retrySuccessorJobRunId != null) ...[
                const Divider(height: 32),
                if (scanDetail.retrySourceJobRunId != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history),
                    title: const Text(JobsMessages.retriedFrom),
                    subtitle: Text(scanDetail.retrySourceJobRunId!.value),
                    onTap: () => onOpenJob(scanDetail.retrySourceJobRunId!),
                  ),
                if (scanDetail.retrySuccessorJobRunId != null)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.forward),
                    title: const Text(JobsMessages.retriedAs),
                    subtitle: Text(scanDetail.retrySuccessorJobRunId!.value),
                    onTap: () => onOpenJob(scanDetail.retrySuccessorJobRunId!),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _retryReasonLabel(RetryNotAdmittedReason reason) => switch (reason) {
    RetryNotAdmittedReasonSourceRunNotTerminal() =>
      JobsMessages.retrySourceRunNotTerminal,
    RetryNotAdmittedReasonOperationNotRetryable() =>
      JobsMessages.retryOperationNotRetryable,
    RetryNotAdmittedReasonNoEligibleTargets() =>
      JobsMessages.retryNoEligibleTargets,
  };
}

class _ProgressFacts extends StatelessWidget {
  const _ProgressFacts({required this.progress});

  final ScanProgressFacts progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${JobsMessages.rootsRequested}: ${progress.rootsRequested}'),
        Text('${JobsMessages.rootsAdmitted}: ${progress.rootsAdmitted}'),
        Text('${JobsMessages.rootsTerminal}: ${progress.rootsTerminal}'),
        if (progress.entriesObserved != null)
          Text('${JobsMessages.entriesObserved}: ${progress.entriesObserved}'),
        if (progress.entriesCommitted != null)
          Text(
            '${JobsMessages.entriesCommitted}: ${progress.entriesCommitted}',
          ),
        if (progress.issueCount != null)
          Text('${JobsMessages.issues}: ${progress.issueCount}'),
      ],
    );
  }
}

String _time(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

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

String _scanStatusLabel(JobScanStatus status) => switch (status) {
  JobScanStatus.running => 'Scanning',
  JobScanStatus.complete => 'Complete',
  JobScanStatus.partial => 'Partial',
  JobScanStatus.failed => 'Failed',
  JobScanStatus.cancelled => 'Cancelled',
  JobScanStatus.abandoned => 'Abandoned',
};
