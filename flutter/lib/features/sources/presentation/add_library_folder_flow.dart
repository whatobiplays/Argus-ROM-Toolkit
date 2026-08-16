import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/add_library_folder_controller.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_folder_picker.dart';
import 'selected_library_folder.dart';
import 'sources_messages.dart';

/// Runs the picker, confirmation, and Add & Scan / Add Without Scanning
/// workflow.
///
/// Picker cancellation performs no mutation. Add & Scan uses the backend
/// composite workflow; transport ambiguity is never replayed as a composite.
Future<void> runAddLibraryFolderFlow(
  BuildContext context,
  WidgetRef ref, {
  required void Function(LibraryRootId rootId) onOpenRoot,
  required void Function(String message) onNotice,
}) async {
  final picker = ref.read(libraryFolderPickerProvider);
  final SelectedLibraryFolder? selected;
  try {
    selected = await picker(context, ref);
  } on Object {
    onNotice(SourcesMessages.pickerFailed);
    return;
  }
  if (selected == null) return;
  if (!context.mounted) return;
  final selectedFolder = selected;
  final capabilities = ref.read(sourcesPresentationCapabilitiesProvider);

  final choice = await showDialog<_AddFolderChoice>(
    context: context,
    builder: (dialogContext) => _AddFolderConfirmationDialog(
      selected: selectedFolder,
      allowScan: capabilities.singleRootScanExecution,
    ),
  );
  if (choice == null || !context.mounted) return;

  final controller = ref.read(
    sourcesAddLibraryFolderControllerProvider.notifier,
  );
  if (choice == _AddFolderChoice.addWithoutScanning) {
    await controller.add(selectedFolder.selection);
  } else {
    await controller.addAndScan(selectedFolder.selection);
  }
  if (!context.mounted) return;
  final operation = ref.read(sourcesAddLibraryFolderControllerProvider);
  switch (operation) {
    case SourcesAddOperationAdded(:final root):
      controller.reset();
      onOpenRoot(root.id);
    case SourcesAddOperationAddedAndScanAdmitted(:final root):
      controller.reset();
      onOpenRoot(root.id);
    case SourcesAddOperationAddedButScanNotAdmitted(:final root, :final issue):
      controller.reset();
      onOpenRoot(root.id);
      if (issue is LibraryScanChildAdmissionIssueAdmissionFailure) {
        onNotice(SourcesMessages.addAndScanAdmissionFailed);
      }
    case SourcesAddOperationScanReconciliationUncertain(:final root):
      final refresh = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(SourcesMessages.addAndScanUncertain),
          content: const Text(SourcesMessages.addAndScanUncertainBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(SourcesMessages.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(SourcesMessages.reconcileNow),
            ),
          ],
        ),
      );
      if (refresh == true && context.mounted) {
        await controller.refreshReconciliation(root.id);
        if (!context.mounted) return;
        final latest = ref.read(sourcesAddLibraryFolderControllerProvider);
        if (latest is SourcesAddOperationAddedAndScanAdmitted) {
          controller.reset();
          onOpenRoot(latest.root.id);
        } else if (latest is SourcesAddOperationScanReconciliationUncertain) {
          onNotice(SourcesMessages.addAndScanUncertainBody);
        }
      } else {
        controller.reset();
        onNotice(SourcesMessages.addAndScanUncertainBody);
      }
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

enum _AddFolderChoice { addAndScan, addWithoutScanning }

/// Confirmation step for one selected local folder.
class _AddFolderConfirmationDialog extends StatelessWidget {
  const _AddFolderConfirmationDialog({
    required this.selected,
    required this.allowScan,
  });

  final SelectedLibraryFolder selected;
  final bool allowScan;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Library Folder?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selected.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            selected.safeLocationPresentation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (allowScan) ...[
            const SizedBox(height: 16),
            const Text(SourcesMessages.addAndScanExplainsNewFolder),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('add-folder-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(SourcesMessages.cancel),
        ),
        TextButton(
          key: const ValueKey<String>('add-folder-without-scan'),
          onPressed: () =>
              Navigator.of(context).pop(_AddFolderChoice.addWithoutScanning),
          child: const Text(SourcesMessages.addWithoutScanning),
        ),
        if (allowScan)
          FilledButton(
            key: const ValueKey<String>('add-folder-and-scan'),
            onPressed: () =>
                Navigator.of(context).pop(_AddFolderChoice.addAndScan),
            child: const Text(SourcesMessages.addAndScan),
          ),
      ],
    );
  }
}
