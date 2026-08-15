import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/root_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remove_root_dialog.dart';
import 'root_sidebar.dart';
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
    super.key,
  });

  final LibraryRootId rootId;

  /// Canonicalizes to /sources when the authoritative root no longer exists.
  final VoidCallback onMissingRoot;

  /// Canonicalizes to /sources after a confirmed removal.
  final VoidCallback onRemoved;

  /// Opens another configured root through the typed route.
  final void Function(LibraryRootId rootId) onOpenRoot;

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
        ) =>
          _RootDetailContent(
            root: root,
            removing: removing,
            removalAmbiguous: removalAmbiguous,
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
    required this.root,
    required this.removing,
    required this.removalAmbiguous,
    required this.onRemove,
  });

  final LibraryRoot root;
  final bool removing;
  final bool removalAmbiguous;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final lastFailureMessage = removalAmbiguous
        ? SourcesMessages.removeAmbiguous
        : null;
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
              Chip(label: const Text(SourcesMessages.neverScanned)),
              if (lastFailureMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  lastFailureMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('sources-remove-library-folder'),
                  // Destructive actions stay unavailable while a removal
                  // outcome is unresolved or a removal is in flight.
                  onPressed: removing || removalAmbiguous ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text(SourcesMessages.removeLibraryFolder),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
