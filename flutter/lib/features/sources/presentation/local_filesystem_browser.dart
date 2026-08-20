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
      // Allow the dialog route to dismiss only when the provider-owned
      // browser is already at its mounted-volume list. While a page is open,
      // Back is consumed locally so the same hierarchy action drives both
      // ordinary and predictive Back.
      canPop: state.page == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_back(controller));
      },
      child: AnimatedPadding(
        duration: kThemeAnimationDuration,
        curve: Curves.easeOut,
        // This boundary may be used directly in tests or a custom surface,
        // not only inside Dialog, so keep it above an active IME locally.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          key: const ValueKey<String>('local-browser-surface'),
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.page?.current.displayName ??
                            'Choose a storage volume',
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _Breadcrumbs(
                    page: page,
                    onBack: () => unawaited(_back(controller)),
                  ),
                ],
                const SizedBox(height: 12),
                _buildBody(context, state, controller),
                if (state.page case final page?) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey<String>('local-browser-select-folder'),
                    onPressed: () => widget.onSelected(
                      SelectedLibraryFolder(
                        selection:
                            LocalFilesystemRootSelection.providerSelection(
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
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LocalFilesystemBrowserState state,
    LocalFilesystemBrowserController controller,
  ) {
    if (state.loading && state.page == null && state.roots.isEmpty) {
      return Center(
        child: Semantics(
          liveRegion: true,
          label: 'Loading mounted storage',
          child: CircularProgressIndicator(),
        ),
      );
    }
    final failure = state.failure;
    if (failure != null && state.page == null && state.roots.isEmpty) {
      return _FailureView(onRetry: controller.retry);
    }
    if (failure != null && state.page == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrowseFailureBanner(
            message: 'Could not refresh mounted storage',
            retryKey: const ValueKey<String>('local-browser-roots-retry'),
            onRetry: controller.retry,
          ),
          _buildRootsList(state, controller),
        ],
      );
    }
    if (state.page == null) {
      if (state.roots.isEmpty) {
        return const Center(child: Text('No mounted storage volumes found'));
      }
      return _buildRootsList(state, controller);
    }
    if (failure != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrowseFailureBanner(
            message: 'Could not load this folder',
            retryKey: const ValueKey<String>('local-browser-browse-retry'),
            onRetry: controller.retry,
          ),
          _buildPageList(state, controller, showLoadMoreFailure: false),
        ],
      );
    }
    return _buildPageList(state, controller, showLoadMoreFailure: true);
  }

  Widget _buildRootsList(
    LocalFilesystemBrowserState state,
    LocalFilesystemBrowserController controller,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.roots.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final root = state.roots[index];
        return ListTile(
          key: ValueKey<String>('local-browser-root-${root.location.value}'),
          leading: const Icon(Icons.sd_storage_outlined),
          title: Text(
            root.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            root.safeLocationPresentation,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => controller.openRoot(root),
        );
      },
    );
  }

  Widget _buildPageList(
    LocalFilesystemBrowserState state,
    LocalFilesystemBrowserController controller, {
    required bool showLoadMoreFailure,
  }) {
    final page = state.page!;
    if (state.loading && page.directories.isEmpty) {
      return Center(
        child: Semantics(
          liveRegion: true,
          label: 'Loading folders',
          child: CircularProgressIndicator(),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: page.directories.length + (page.nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= page.directories.length) {
          if (state.loadingMore) {
            return ListTile(
              leading: Semantics(
                liveRegion: true,
                label: 'Loading more folders',
                child: CircularProgressIndicator(),
              ),
              title: const Text('Loading more folders…'),
            );
          }
          if (showLoadMoreFailure && state.failure != null) {
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
          title: Text(
            directory.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
          Semantics(
            liveRegion: true,
            label: 'Could not load mounted storage',
            child: Text('Could not load mounted storage'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _BrowseFailureBanner extends StatelessWidget {
  const _BrowseFailureBanner({
    required this.message,
    required this.retryKey,
    required this.onRetry,
  });

  final String message;
  final Key retryKey;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.errorContainer,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            label: message,
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: retryKey,
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}
