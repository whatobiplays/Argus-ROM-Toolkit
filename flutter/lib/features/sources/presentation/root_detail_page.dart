import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/root_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remove_root_dialog.dart';
import 'root_sidebar.dart';
import 'source_hierarchy_browser.dart';
import 'sources_messages.dart';

/// One configured root's detail surface.
///
/// Presentation only: navigation is callback-driven and all displayed state
/// comes from focused authoritative reads.
class SourcesRootDetailPage extends ConsumerWidget {
  const SourcesRootDetailPage({
    required this.rootId,
    required this.onMissingRoot,
    required this.onRemoved,
    required this.onOpenRoot,
    required this.onOpenJob,
    super.key,
  });

  final LibraryRootId rootId;

  /// Canonicalizes to /sources when the authoritative root no longer exists.
  final VoidCallback onMissingRoot;

  /// Canonicalizes to /sources after a confirmed removal.
  final VoidCallback onRemoved;

  /// Opens another configured root through the typed route.
  final void Function(LibraryRootId rootId) onOpenRoot;

  /// Opens one durable job detail through the typed Jobs route.
  final void Function(JobRunId jobRunId) onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sourcesRootDetailControllerProvider(rootId));
    ref.listen(sourcesRootDetailControllerProvider(rootId), (previous, next) {
      final value = next.value;
      if (value is SourcesRootDetailStateMissing) {
        onMissingRoot();
      }
    });

    final content = detail.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(SourcesMessages.loadFailed),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref
                    .read(sourcesRootDetailControllerProvider(rootId).notifier)
                    .refresh(rootId),
                child: const Text(SourcesMessages.retry),
              ),
            ],
          ),
        ),
      ),
      data: (state) => switch (state) {
        SourcesRootDetailStateMissing() => const SizedBox.shrink(),
        SourcesRootDetailStateReady(
          :final root,
          :final removing,
          :final removalAmbiguous,
          :final scanning,
          :final admittedScanJobRunId,
          :final removalBlockedByActiveScan,
        ) =>
          _RootDetailContent(
            rootId: rootId,
            root: root,
            removing: removing,
            removalAmbiguous: removalAmbiguous,
            scanning: scanning,
            admittedScanJobRunId: admittedScanJobRunId,
            removalBlockedByActiveScan: removalBlockedByActiveScan,
            onOpenJob: onOpenJob,
            onScan: () async {
              final jobRunId = await ref
                  .read(sourcesRootDetailControllerProvider(rootId).notifier)
                  .startScan(rootId);
              if (jobRunId != null && context.mounted) {
                onOpenJob(jobRunId);
              }
            },
            onRemove: () async {
              final confirmed = await showRemoveRootConfirmation(
                context,
                root: root,
              );
              if (confirmed && context.mounted) {
                await ref
                    .read(sourcesRootDetailControllerProvider(rootId).notifier)
                    .remove(rootId);
                final latest = ref.read(
                  sourcesRootDetailControllerProvider(rootId),
                );
                if (latest.value is SourcesRootDetailStateMissing) {
                  onRemoved();
                }
              }
            },
          ),
      },
    );

    if (!sourcesUsesSidebarLayout(context)) {
      return content;
    }
    return Row(
      children: [
        SourcesRootSidebar(selectedRootId: rootId, onOpenRoot: onOpenRoot),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
  }
}

class _RootDetailContent extends StatelessWidget {
  const _RootDetailContent({
    required this.rootId,
    required this.root,
    required this.removing,
    required this.removalAmbiguous,
    required this.scanning,
    required this.admittedScanJobRunId,
    required this.removalBlockedByActiveScan,
    required this.onOpenJob,
    required this.onScan,
    required this.onRemove,
  });

  final LibraryRoot root;
  final LibraryRootId rootId;
  final bool removing;
  final bool removalAmbiguous;
  final bool scanning;
  final JobRunId? admittedScanJobRunId;
  final bool removalBlockedByActiveScan;
  final void Function(JobRunId jobRunId) onOpenJob;
  final VoidCallback onScan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final lastFailureMessage = removalAmbiguous
        ? SourcesMessages.removeAmbiguous
        : null;
    final activeScan = root.activeScan;
    final lastScan = root.lastScan;
    final canScan = activeScan == null;
    final statusLabel = activeScan != null
        ? SourcesMessages.scanningInProgress
        : lastScan != null
        ? SourcesMessages.lastScanStatus(lastScan.status)
        : SourcesMessages.neverScanned;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                root.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(root.safeLocationPresentation),
              const SizedBox(height: 12),
              Chip(label: Text(statusLabel)),
              if (activeScan != null || admittedScanJobRunId != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey<String>('sources-view-job'),
                  onPressed: () {
                    final JobRunId? jobRunId = activeScan != null
                        ? JobRunId(activeScan.jobRunId)
                        : admittedScanJobRunId;
                    if (jobRunId != null) {
                      onOpenJob(jobRunId);
                    }
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text(SourcesMessages.viewJob),
                ),
              ],
              if (activeScan == null && lastScan != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey<String>('sources-view-last-job'),
                  onPressed: () => onOpenJob(JobRunId(lastScan.jobRunId)),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text(SourcesMessages.viewJob),
                ),
              ],
              if (removalBlockedByActiveScan) ...[
                const SizedBox(height: 12),
                Text(
                  SourcesMessages.rootHasActiveScan,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (lastFailureMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  lastFailureMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(child: SourceHierarchyBrowser(rootId: rootId)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (canScan) ...[
                    FilledButton.icon(
                      key: const ValueKey<String>('sources-start-scan'),
                      onPressed: scanning ? null : onScan,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        lastScan == null
                            ? SourcesMessages.scan
                            : SourcesMessages.scanAgain,
                      ),
                    ),
                    const Spacer(),
                  ],
                  OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'sources-remove-library-folder',
                    ),
                    // Destructive actions stay unavailable while a removal
                    // outcome is unresolved or a removal is in flight.
                    onPressed: removing || removalAmbiguous ? null : onRemove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text(SourcesMessages.removeLibraryFolder),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
