import 'package:flutter/material.dart';

/// Central palette + text theme, matching the Join Hub design prototype:
/// cool paper neutrals, a goldenrod accent reserved for primary actions,
/// and a separate green reserved for "joined" success state.
class AppTheme {
  AppTheme._();

  static const accent = Color(0xFFB8791F);
  static const good = Color(0xFF2F8558);
  static const goodBg = Color(0xFFDCEFE3);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(surface: const Color(0xFFFFFFFF));

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFEEF1EC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Color(0xFF141A2B),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0E1220),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
