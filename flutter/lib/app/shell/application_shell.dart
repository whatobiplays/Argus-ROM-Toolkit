import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';

/// Hosts routed content and adapts the application's navigation presentation.
class ApplicationShell extends StatelessWidget {
  /// Creates the persistent adaptive shell.
  const ApplicationShell({
    required this.currentDestination,
    required this.onSettingsSelected,
    required this.child,
    super.key,
  });

  /// The destination derived from the current router location.
  final AppDestination? currentDestination;

  /// Navigates to the typed Settings route at the composition boundary.
  final VoidCallback onSettingsSelected;

  /// The routed destination content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);

    return switch (sizeClass) {
      WindowSizeClass.compact => _CompactShell(
        onSettingsSelected: onSettingsSelected,
        child: child,
      ),
      WindowSizeClass.medium => _RailShell(
        currentDestination: currentDestination,
        extended: false,
        key: const ValueKey<String>('medium-navigation-rail'),
        onSettingsSelected: onSettingsSelected,
        child: child,
      ),
      WindowSizeClass.expanded => _RailShell(
        currentDestination: currentDestination,
        extended: true,
        key: const ValueKey<String>('expanded-navigation-sidebar'),
        onSettingsSelected: onSettingsSelected,
        child: child,
      ),
      WindowSizeClass.large => _RailShell(
        currentDestination: currentDestination,
        extended: true,
        key: const ValueKey<String>('large-navigation-sidebar'),
        onSettingsSelected: onSettingsSelected,
        child: child,
      ),
    };
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.child, required this.onSettingsSelected});

  final Widget child;
  final VoidCallback onSettingsSelected;

  Future<void> _showMore(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onSettingsSelected();
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomAppBar(
        child: Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            button: true,
            label: 'More',
            child: IconButton(
              key: const ValueKey<String>('compact-more-button'),
              icon: const Icon(Icons.more_horiz),
              tooltip: 'More',
              onPressed: () => _showMore(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailShell extends StatelessWidget {
  const _RailShell({
    required this.child,
    required this.currentDestination,
    required this.extended,
    required this.onSettingsSelected,
    super.key,
  });

  final Widget child;
  final AppDestination? currentDestination;
  final bool extended;
  final VoidCallback onSettingsSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = currentDestination == AppDestination.settings
        ? 0
        : null;

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            extended: extended,
            labelType: extended ? null : NavigationRailLabelType.none,
            selectedIndex: selectedIndex,
            onDestinationSelected: (_) => onSettingsSelected(),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
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
