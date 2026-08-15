import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';

import 'sources_messages.dart';

/// Shows the explicit destructive confirmation before root removal.
///
/// The copy always states that Argus configuration/index state is removed
/// while files on disk are unchanged.
Future<bool> showRemoveRootConfirmation(
  BuildContext context, {
  required LibraryRoot root,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(SourcesMessages.removeConfirmationTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            root.displayName,
            style: Theme.of(dialogContext).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            root.safeLocationPresentation,
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(SourcesMessages.removeConfirmationBody),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('remove-root-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(SourcesMessages.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('remove-root-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(SourcesMessages.remove),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
