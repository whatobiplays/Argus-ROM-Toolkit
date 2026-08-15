import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sources_session_presentation.g.dart';

/// Explicit session-only Sources sidebar override.
enum SourcesSidebarOverride { none, collapsed, expanded }

/// Session-only owner of the explicit root-sidebar preference.
///
/// `none` means the adaptive default applies; an explicit choice wins until a
/// fresh Flutter application/provider scope is created. This state is never
/// persisted.
@Riverpod(keepAlive: true)
class SourcesSidebarPreference extends _$SourcesSidebarPreference {
  @override
  SourcesSidebarOverride build() => SourcesSidebarOverride.none;

  /// Collapses the Sources root sidebar for the remainder of the session.
  void collapse() {
    state = SourcesSidebarOverride.collapsed;
  }

  /// Expands the Sources root sidebar for the remainder of the session.
  void expand() {
    state = SourcesSidebarOverride.expanded;
  }
}
