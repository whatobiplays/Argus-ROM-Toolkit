/// Application-wide structural width classes, measured in logical pixels.
enum WindowSizeClass { compact, medium, expanded, large }

const double _mediumWidth = 600;
const double _expandedWidth = 840;
const double _largeWidth = 1200;

/// Classifies available application width without consulting platform or
/// hardware identity.
WindowSizeClass classifyWindowWidth(double width) {
  if (width < _mediumWidth) {
    return WindowSizeClass.compact;
  }
  if (width < _expandedWidth) {
    return WindowSizeClass.medium;
  }
  if (width < _largeWidth) {
    return WindowSizeClass.expanded;
  }
  return WindowSizeClass.large;
}

/// Returns the page-content gutter for an application structural class.
double pageGutterFor(WindowSizeClass sizeClass) => switch (sizeClass) {
  WindowSizeClass.compact => 16,
  WindowSizeClass.medium => 24,
  WindowSizeClass.expanded || WindowSizeClass.large => 32,
};
