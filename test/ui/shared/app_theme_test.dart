import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme exposes the approved semantic palette and typography', () {
    final theme = AppTheme.light();

    expect(theme.colorScheme.primary, const Color(0xFF0F766E));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF6FAF9));
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(theme.textTheme.headlineSmall?.fontFamily, 'Outfit');
  });

  test('dark theme keeps teal actions on dark neutral surfaces', () {
    final theme = AppTheme.dark();

    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFF5EEAD4));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF071B1D));
  });

  test('theme controls meet the approved geometry', () {
    final theme = AppTheme.light();
    final filledSize = theme.filledButtonTheme.style?.minimumSize?.resolve({});
    final iconConstraints = theme.iconButtonTheme.style?.minimumSize?.resolve(
      {},
    );
    final border = theme.inputDecorationTheme.border as OutlineInputBorder;

    expect(filledSize?.height, greaterThanOrEqualTo(52));
    expect(iconConstraints?.height, greaterThanOrEqualTo(44));
    expect(border.borderRadius, BorderRadius.circular(12));
  });
}
