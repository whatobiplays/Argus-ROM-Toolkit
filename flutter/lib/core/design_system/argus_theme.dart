import 'package:flutter/material.dart';

/// Owns the replaceable Material theme data used by the application root.
abstract final class ArgusTheme {
  static const Color _seedColor = Color(0xff4f6359);

  /// The production light Material 3 theme.
  static final ThemeData light = _build(Brightness.light);

  /// The production dark Material 3 theme.
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
