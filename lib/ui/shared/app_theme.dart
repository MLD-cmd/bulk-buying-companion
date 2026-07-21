import 'package:flutter/material.dart';

/// Replaces Android's default edge-of-list stretch effect with the glow
/// indicator used elsewhere, so scrolling doesn't visibly distort content.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: Theme.of(context).colorScheme.primary,
      child: child,
    );
  }
}

/// Shared visual language for the campus co-op experience.
///
/// Screens consume semantic roles from [ColorScheme] and these few additional
/// lifecycle colors instead of introducing feature-specific palettes.
class AppTheme {
  AppTheme._();

  static const primary = Color(0xFF0F766E);
  static const success = Color(0xFF166534);
  static const successContainer = Color(0xFFE7F6EC);
  static const onSuccessContainer = Color(0xFF14532D);
  static const warning = Color(0xFF8A4B08);
  static const warningContainer = Color(0xFFFFF3D6);
  static const onWarningContainer = Color(0xFF713F12);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCCFBF1),
    onPrimaryContainer: Color(0xFF134E4A),
    secondary: Color(0xFF0E7490),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCFFAFE),
    onSecondaryContainer: Color(0xFF164E63),
    tertiary: warning,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: warningContainer,
    onTertiaryContainer: onWarningContainer,
    error: Color(0xFFB42318),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDECEA),
    onErrorContainer: Color(0xFF7A271A),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF102A2E),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF0F7F5),
    surfaceContainer: Color(0xFFE7F1EF),
    surfaceContainerHigh: Color(0xFFDCE9E7),
    surfaceContainerHighest: Color(0xFFD0DFDC),
    onSurfaceVariant: Color(0xFF52666A),
    outline: Color(0xFF829794),
    outlineVariant: Color(0xFFCBD8D6),
    shadow: Color(0xFF071B1D),
    scrim: Color(0xFF071B1D),
    inverseSurface: Color(0xFF1E3437),
    onInverseSurface: Color(0xFFF2FBF9),
    inversePrimary: Color(0xFF5EEAD4),
    surfaceTint: primary,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF5EEAD4),
    onPrimary: Color(0xFF042F2E),
    primaryContainer: Color(0xFF115E59),
    onPrimaryContainer: Color(0xFFCCFBF1),
    secondary: Color(0xFF67E8F9),
    onSecondary: Color(0xFF083344),
    secondaryContainer: Color(0xFF155E75),
    onSecondaryContainer: Color(0xFFCFFAFE),
    tertiary: Color(0xFFFBBF24),
    onTertiary: Color(0xFF451A03),
    tertiaryContainer: Color(0xFF713F12),
    onTertiaryContainer: Color(0xFFFFF3D6),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0B2426),
    onSurface: Color(0xFFE8F5F3),
    surfaceContainerLowest: Color(0xFF041315),
    surfaceContainerLow: Color(0xFF102B2D),
    surfaceContainer: Color(0xFF163234),
    surfaceContainerHigh: Color(0xFF1D3A3C),
    surfaceContainerHighest: Color(0xFF284548),
    onSurfaceVariant: Color(0xFFB5C9C6),
    outline: Color(0xFF809592),
    outlineVariant: Color(0xFF3E5351),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE8F5F3),
    onInverseSurface: Color(0xFF173336),
    inversePrimary: primary,
    surfaceTint: Color(0xFF5EEAD4),
  );

  static ThemeData light() => _build(
    colorScheme: _lightScheme,
    scaffoldBackgroundColor: const Color(0xFFF6FAF9),
  );

  static ThemeData dark() => _build(
    colorScheme: _darkScheme,
    scaffoldBackgroundColor: const Color(0xFF071B1D),
  );

  static ThemeData _build({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
  }) {
    final baseTextTheme = ThemeData(
      brightness: colorScheme.brightness,
      useMaterial3: true,
    ).textTheme;
    final bodyColor = colorScheme.onSurface;
    final mutedColor = colorScheme.onSurfaceVariant;

    TextStyle body(TextStyle? source, {FontWeight? weight}) =>
        (source ?? const TextStyle()).copyWith(
          fontFamily: 'Manrope',
          color: bodyColor,
          fontWeight: weight,
          height: 1.35,
        );

    TextStyle heading(
      TextStyle? source, {
      FontWeight weight = FontWeight.w500,
    }) => (source ?? const TextStyle()).copyWith(
      fontFamily: 'Outfit',
      color: bodyColor,
      fontWeight: weight,
      height: 1.15,
      letterSpacing: -0.2,
    );

    final textTheme = baseTextTheme.copyWith(
      displayLarge: heading(baseTextTheme.displayLarge),
      displayMedium: heading(baseTextTheme.displayMedium),
      displaySmall: heading(baseTextTheme.displaySmall),
      headlineLarge: heading(baseTextTheme.headlineLarge),
      headlineMedium: heading(baseTextTheme.headlineMedium),
      headlineSmall: heading(baseTextTheme.headlineSmall),
      titleLarge: heading(baseTextTheme.titleLarge),
      titleMedium: heading(baseTextTheme.titleMedium),
      titleSmall: heading(baseTextTheme.titleSmall),
      bodyLarge: body(baseTextTheme.bodyLarge),
      bodyMedium: body(baseTextTheme.bodyMedium),
      bodySmall: body(
        baseTextTheme.bodySmall,
      ).copyWith(color: mutedColor, fontSize: 14),
      labelLarge: body(baseTextTheme.labelLarge, weight: FontWeight.w500),
      labelMedium: body(
        baseTextTheme.labelMedium,
        weight: FontWeight.w500,
      ).copyWith(fontSize: 14),
      labelSmall: body(
        baseTextTheme.labelSmall,
        weight: FontWeight.w500,
      ).copyWith(fontSize: 12),
    );

    const controlRadius = BorderRadius.all(Radius.circular(12));
    final defaultBorder = OutlineInputBorder(
      borderRadius: controlRadius,
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      fontFamily: 'Manrope',
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        titleSpacing: 20,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: const RoundedRectangleBorder(borderRadius: controlRadius),
          side: BorderSide(color: colorScheme.outline),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: const RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size.square(44)),
          iconSize: WidgetStatePropertyAll(20),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: textTheme.labelLarge?.copyWith(
          color: colorScheme.onPrimary,
          fontSize: 15,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: defaultBorder,
        enabledBorder: defaultBorder,
        focusedBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: defaultBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surface,
        selectedColor: colorScheme.primaryContainer,
        disabledColor: colorScheme.surfaceContainerHigh,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: colorScheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
    );
  }
}
