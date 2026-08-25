import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Hosts routed content and adapts the application's navigation presentation.
class ApplicationShell extends ConsumerWidget {
  /// Creates the persistent adaptive shell.
  const ApplicationShell({
    required this.currentDestination,
    this.onLibrarySelected,
    required this.onSettingsSelected,
    required this.onSourcesSelected,
    required this.onJobsSelected,
    required this.child,
    super.key,
  });

  /// The destination derived from the current router location.
  final AppDestination? currentDestination;

  /// Navigates to the typed Library route. A null value keeps legacy direct
  /// shell fixtures on the pre-Phase-003 three-destination presentation.
  final VoidCallback? onLibrarySelected;

  /// Navigates to the typed Settings route at the composition boundary.
  final VoidCallback onSettingsSelected;

  /// Navigates to the typed Sources route at the composition boundary.
  final VoidCallback onSourcesSelected;

  /// Navigates to the typed Jobs route at the composition boundary.
  final VoidCallback onJobsSelected;

  /// The routed destination content.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);
    final activeSummary =
        ref.watch(activeJobSummaryControllerProvider).value ??
        const ActiveJobSummary(activeCount: 0);

    return switch (sizeClass) {
      WindowSizeClass.compact => _CompactShell(
        currentDestination: currentDestination,
        activeSummary: activeSummary,
        onLibrarySelected: onLibrarySelected,
        onJobsSelected: onJobsSelected,
        onSettingsSelected: onSettingsSelected,
        onSourcesSelected: onSourcesSelected,
        child: child,
      ),
      WindowSizeClass.medium => _RailShell(
        currentDestination: currentDestination,
        extended: false,
        activeSummary: activeSummary,
        key: const ValueKey<String>('medium-navigation-rail'),
        onLibrarySelected: onLibrarySelected,
        onSettingsSelected: onSettingsSelected,
        onSourcesSelected: onSourcesSelected,
        onJobsSelected: onJobsSelected,
        child: child,
      ),
      WindowSizeClass.expanded => _RailShell(
        currentDestination: currentDestination,
        extended: true,
        activeSummary: activeSummary,
        key: const ValueKey<String>('expanded-navigation-sidebar'),
        onLibrarySelected: onLibrarySelected,
        onSettingsSelected: onSettingsSelected,
        onSourcesSelected: onSourcesSelected,
        onJobsSelected: onJobsSelected,
        child: child,
      ),
      WindowSizeClass.large => _RailShell(
        currentDestination: currentDestination,
        extended: true,
        activeSummary: activeSummary,
        key: const ValueKey<String>('large-navigation-sidebar'),
        onLibrarySelected: onLibrarySelected,
        onSettingsSelected: onSettingsSelected,
        onSourcesSelected: onSourcesSelected,
        onJobsSelected: onJobsSelected,
        child: child,
      ),
    };
  }
}

/// Router-aware owner of the SPEC-FE-004 stateful branch model.
///
/// Each semantic destination keeps its own last durable route; selecting an
/// inactive destination restores its branch, and reselecting the active
/// destination returns that branch to its canonical root.
class BranchAwareShell extends ConsumerStatefulWidget {
  /// Creates the branch-aware shell wrapper.
  const BranchAwareShell({
    required this.currentUri,
    required this.currentDestination,
    required this.child,
    this.includeLibrary = false,
    super.key,
  });

  /// The current router location.
  final Uri currentUri;

  /// The destination derived from the current router location.
  final AppDestination? currentDestination;

  /// The routed destination content.
  final Widget child;

  /// Production routes opt into the Phase 003 Library branch. The default
  /// preserves older embedding shells that have no Library route.
  final bool includeLibrary;

  @override
  ConsumerState<BranchAwareShell> createState() => _BranchAwareShellState();
}

class _BranchAwareShellState extends ConsumerState<BranchAwareShell> {
  final Map<AppDestination, String> _branches = {};

  void _selectDestination(AppDestination destination, String canonicalRoot) {
    final current = widget.currentDestination;
    if (current == destination) {
      context.go(canonicalRoot);
      return;
    }
    if (current != null) {
      _branches[current] = widget.currentUri.path;
    }
    final target = _branches[destination] ?? canonicalRoot;
    context.go(target);
  }

  void _openJobs(ActiveJobSummary summary) {
    if (summary.activeCount == 1 && summary.soleActiveJobRunId != null) {
      _selectDestination(
        AppDestination.jobs,
        '/jobs/${summary.soleActiveJobRunId!.value}',
      );
      return;
    }
    _selectDestination(AppDestination.jobs, '/jobs');
  }

  @override
  Widget build(BuildContext context) {
    final activeSummary =
        ref.watch(activeJobSummaryControllerProvider).value ??
        const ActiveJobSummary(activeCount: 0);
    return ApplicationShell(
      currentDestination: widget.currentDestination,
      onLibrarySelected: widget.includeLibrary
          ? () => _selectDestination(AppDestination.library, '/library')
          : null,
      onSettingsSelected: () =>
          _selectDestination(AppDestination.settings, '/settings'),
      onSourcesSelected: () =>
          _selectDestination(AppDestination.sources, '/sources'),
      onJobsSelected: () => _openJobs(activeSummary),
      child: widget.child,
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.currentDestination,
    required this.activeSummary,
    required this.onLibrarySelected,
    required this.onJobsSelected,
    required this.onSettingsSelected,
    required this.onSourcesSelected,
    required this.child,
  });

  final AppDestination? currentDestination;
  final ActiveJobSummary activeSummary;
  final VoidCallback? onLibrarySelected;
  final VoidCallback onJobsSelected;
  final VoidCallback onSettingsSelected;
  final VoidCallback onSourcesSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final legacy = onLibrarySelected == null;
    final selectedIndex = legacy
        ? switch (currentDestination) {
            AppDestination.sources => 0,
            AppDestination.jobs => 1,
            AppDestination.settings => 2,
            _ => 0,
          }
        : switch (currentDestination) {
            AppDestination.library => 0,
            AppDestination.sources => 1,
            AppDestination.jobs => 2,
            AppDestination.settings => 3,
            null => 0,
          };
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        key: const ValueKey<String>('compact-navigation-bar'),
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => legacy
            ? switch (index) {
                0 => onSourcesSelected(),
                1 => onJobsSelected(),
                2 => onSettingsSelected(),
                _ => null,
              }
            : switch (index) {
                0 => onLibrarySelected!(),
                1 => onSourcesSelected(),
                2 => onJobsSelected(),
                3 => onSettingsSelected(),
                _ => null,
              },
        destinations: legacy
            ? <NavigationDestination>[
                const NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Sources',
                ),
                jobsNavigationDestination(activeSummary),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ]
            : <NavigationDestination>[
                const NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Library',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Sources',
                ),
                jobsNavigationDestination(activeSummary),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
      ),
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({
    required this.child,
    required this.currentDestination,
    required this.extended,
    required this.activeSummary,
    required this.onLibrarySelected,
    required this.onSettingsSelected,
    required this.onSourcesSelected,
    required this.onJobsSelected,
    super.key,
  });

  final Widget child;
  final AppDestination? currentDestination;
  final bool extended;
  final ActiveJobSummary activeSummary;
  final VoidCallback? onLibrarySelected;
  final VoidCallback onSettingsSelected;
  final VoidCallback onSourcesSelected;
  final VoidCallback onJobsSelected;

  @override
  Widget build(BuildContext context) {
    final legacy = onLibrarySelected == null;
    final selectedIndex = legacy
        ? switch (currentDestination) {
            AppDestination.jobs => 0,
            AppDestination.sources => 1,
            AppDestination.settings => 2,
            _ => null,
          }
        : switch (currentDestination) {
            AppDestination.library => 0,
            AppDestination.jobs => 2,
            AppDestination.sources => 1,
            AppDestination.settings => 3,
            null => null,
          };

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            extended: extended,
            labelType: extended ? null : NavigationRailLabelType.none,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => legacy
                ? switch (index) {
                    0 => onJobsSelected(),
                    1 => onSourcesSelected(),
                    2 => onSettingsSelected(),
                    _ => null,
                  }
                : switch (index) {
                    0 => onLibrarySelected!(),
                    1 => onSourcesSelected(),
                    2 => onJobsSelected(),
                    3 => onSettingsSelected(),
                    _ => null,
                  },
            destinations: legacy
                ? <NavigationRailDestination>[
                    _jobsRailDestination(activeSummary),
                    const NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('Sources'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ]
                : <NavigationRailDestination>[
                    const NavigationRailDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view),
                      label: Text('Library'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('Sources'),
                    ),
                    _jobsRailDestination(activeSummary),
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

NavigationRailDestination _jobsRailDestination(ActiveJobSummary summary) {
  final icon = summary.activeCount > 0
      ? Badge(
          label: Text('${summary.activeCount}'),
          child: const Icon(Icons.receipt_long_outlined),
        )
      : const Icon(Icons.receipt_long_outlined);
  return NavigationRailDestination(
    icon: icon,
    selectedIcon: summary.activeCount > 0
        ? Badge(
            label: Text('${summary.activeCount}'),
            child: const Icon(Icons.receipt_long),
          )
        : const Icon(Icons.receipt_long),
    label: const Text('Jobs'),
  );
}

NavigationDestination jobsNavigationDestination(ActiveJobSummary summary) {
  final icon = summary.activeCount > 0
      ? Badge(
          label: Text('${summary.activeCount}'),
          child: const Icon(Icons.receipt_long_outlined),
        )
      : const Icon(Icons.receipt_long_outlined);
  return NavigationDestination(
    icon: icon,
    selectedIcon: summary.activeCount > 0
        ? Badge(
            label: Text('${summary.activeCount}'),
            child: const Icon(Icons.receipt_long),
          )
        : const Icon(Icons.receipt_long),
    label: 'Jobs',
  );
}
