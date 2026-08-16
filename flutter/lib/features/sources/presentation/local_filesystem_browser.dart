import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/local_filesystem_browser_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'selected_library_folder.dart';

/// Argus-owned mounted-volume and directory browser.
class LocalFilesystemBrowser extends ConsumerStatefulWidget {
  const LocalFilesystemBrowser({
    required this.onSelected,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<SelectedLibraryFolder> onSelected;
  final VoidCallback onCancel;

  @override
  ConsumerState<LocalFilesystemBrowser> createState() =>
      _LocalFilesystemBrowserState();
}

class _LocalFilesystemBrowserState
    extends ConsumerState<LocalFilesystemBrowser> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(
      () => ref.read(localFilesystemBrowserControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localFilesystemBrowserControllerProvider);
    final controller = ref.read(
      localFilesystemBrowserControllerProvider.notifier,
    );
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_back(controller));
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.page?.current.displayName ??
                          'Choose a storage volume',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('local-browser-cancel'),
                    tooltip: 'Cancel',
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (state.page case final page?) ...[
                Text(
                  page.current.safeLocationPresentation,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _Breadcrumbs(
                  page: page,
                  onBack: () => unawaited(_back(controller)),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(child: _buildBody(context, state, controller)),
              if (state.page case final page?) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey<String>('local-browser-select-folder'),
                  onPressed: () => widget.onSelected(
                    SelectedLibraryFolder(
                      selection: LocalFilesystemRootSelection.providerSelection(
                        page.current.location.value,
                      ),
                      displayName: page.current.displayName,
                      safeLocationPresentation:
                          page.current.safeLocationPresentation,
                    ),
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Select this folder'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LocalFilesystemBrowserState state,
    LocalFilesystemBrowserController controller,
  ) {
    if (state.loading && state.page == null && state.roots.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final failure = state.failure;
    if (failure != null && state.page == null && state.roots.isEmpty) {
      return _FailureView(onRetry: controller.retry);
    }
    if (state.page == null) {
      if (state.roots.isEmpty) {
        return const Center(child: Text('No mounted storage volumes found'));
      }
      return ListView.separated(
        itemCount: state.roots.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final root = state.roots[index];
          return ListTile(
            key: ValueKey<String>('local-browser-root-${root.location.value}'),
            leading: const Icon(Icons.sd_storage_outlined),
            title: Text(root.displayName),
            subtitle: Text(root.safeLocationPresentation),
            onTap: () => controller.openRoot(root),
          );
        },
      );
    }
    final page = state.page!;
    if (state.loading && page.directories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.separated(
      itemCount: page.directories.length + (page.nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= page.directories.length) {
          if (state.loadingMore) {
            return const ListTile(
              leading: CircularProgressIndicator(),
              title: Text('Loading more folders…'),
            );
          }
          if (failure != null) {
            return ListTile(
              key: const ValueKey<String>('local-browser-load-more-retry'),
              title: const Text('Could not load more folders'),
              trailing: TextButton(
                onPressed: controller.retry,
                child: const Text('Retry'),
              ),
            );
          }
          return ListTile(
            key: const ValueKey<String>('local-browser-load-more'),
            title: const Text('Load more folders'),
            trailing: const Icon(Icons.expand_more),
            onTap: controller.loadMore,
          );
        }
        final directory = page.directories[index];
        return ListTile(
          key: ValueKey<String>(
            'local-browser-directory-${directory.location.value}',
          ),
          leading: const Icon(Icons.folder_outlined),
          title: Text(directory.displayName),
          onTap: () => controller.openDirectory(directory),
        );
      },
    );
  }

  Future<void> _back(LocalFilesystemBrowserController controller) async {
    final moved = await controller.back();
    if (!moved && mounted) widget.onCancel();
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.page, required this.onBack});

  final LocalFilesystemBrowsePage page;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (page.breadcrumbs.length > 1)
            TextButton.icon(
              key: const ValueKey<String>('local-browser-up'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Up'),
            ),
          for (final breadcrumb in page.breadcrumbs)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                breadcrumb.displayName,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
        ],
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load mounted storage'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
