import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/source_entry_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sources_messages.dart';

/// Focused detail surface for one selected source entry.
///
/// Shows only safe application-owned facts: display name, display location,
/// kind, and classification. No provenance, locators, or persistence details.
class SourceEntryInspector extends ConsumerWidget {
  const SourceEntryInspector({
    required this.rootId,
    required this.entryId,
    super.key,
  });

  final LibraryRootId rootId;
  final SourceEntryId entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(
      sourceEntryDetailControllerProvider(
        rootId: rootId,
        sourceEntryId: entryId,
      ),
    );
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: detail.when(
            loading: () =>
                const Center(child: Text(SourcesMessages.entryDetailsLoading)),
            error: (error, stackTrace) => Center(
              child: Text(
                SourcesMessages.entryDetailsFailed,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            data: (entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  SourcesMessages.entryDetails,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(entry.displayName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(entry.displayLocation),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(SourcesMessages.entryKindLabel(entry.kind)),
                    ),
                    Chip(
                      label: Text(
                        SourcesMessages.entryClassificationLabel(
                          entry.classification,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
