import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/add_library_folder_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_folder_picker.dart';
import 'sources_messages.dart';

/// Runs the picker, confirmation, and root-only add workflow.
///
/// Picker cancellation performs no mutation. The confirmation surface is
/// root-only: it exposes Add Library Folder while scanning is unavailable,
/// and later slices can evolve the same authority path into Add & Scan.
Future<void> runAddLibraryFolderFlow(
  BuildContext context,
  WidgetRef ref, {
  required void Function(LibraryRootId rootId) onOpenRoot,
  required void Function(String message) onNotice,
}) async {
  final picker = ref.read(libraryFolderPickerProvider);
  final LocalFilesystemRootSelection? selection;
  try {
    selection = await picker();
  } on Object {
    onNotice(SourcesMessages.pickerFailed);
    return;
  }
  if (selection == null) return;
  if (!context.mounted) return;
  final safeSelection = selection;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _AddFolderConfirmationDialog(selection: safeSelection),
  );
  if (confirmed != true || !context.mounted) return;

  final controller = ref.read(
    sourcesAddLibraryFolderControllerProvider.notifier,
  );
  await controller.add(safeSelection);
  if (!context.mounted) return;
  final operation = ref.read(sourcesAddLibraryFolderControllerProvider);
  switch (operation) {
    case SourcesAddOperationAdded(:final root):
      controller.reset();
      onOpenRoot(root.id);
    case SourcesAddOperationAlreadyConfigured(:final existingLibraryRootId):
      controller.reset();
      onOpenRoot(existingLibraryRootId);
    case SourcesAddOperationOverlapsExisting(:final existingLibraryRootId):
      controller.reset();
      final open = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(SourcesMessages.folderOverlapsExisting),
          content: const Text(SourcesMessages.folderAlreadyConfigured),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(SourcesMessages.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(SourcesMessages.openExistingFolder),
            ),
          ],
        ),
      );
      if (open == true) onOpenRoot(existingLibraryRootId);
    case SourcesAddOperationFailed():
      controller.reset();
      onNotice(SourcesMessages.addFailed);
    case SourcesAddOperationAmbiguous():
      controller.reset();
      onNotice(SourcesMessages.addAmbiguous);
    case SourcesAddOperationIdle() || SourcesAddOperationSubmitting():
      break;
  }
}

/// Root-only confirmation step for one selected local folder.
class _AddFolderConfirmationDialog extends StatelessWidget {
  const _AddFolderConfirmationDialog({required this.selection});

  final LocalFilesystemRootSelection selection;

  @override
  Widget build(BuildContext context) {
    final folderName = _folderName(selection.selectedFolderPath);
    return AlertDialog(
      title: const Text('Add Library Folder?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(folderName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            selection.selectedFolderPath,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(SourcesMessages.scanningUnavailableNote),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('add-folder-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(SourcesMessages.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('add-folder-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(SourcesMessages.addLibraryFolder),
        ),
      ],
    );
  }
}

String _folderName(String path) {
  final separatorIndex = path.lastIndexOf(RegExp(r'[/\\]'));
  if (separatorIndex == -1 || separatorIndex == path.length - 1) {
    return path;
  }
  return path.substring(separatorIndex + 1);
}
