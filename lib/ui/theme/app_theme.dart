import 'package:flutter/material.dart';

/// Colors taken from the HomeTrack Hub logo.
abstract final class BrandColors {
  /// The house, the "M" and the "HomeTrack Hub" lettering.
  static const navy = Color(0xFF122430);

  /// The "S" and the leaves.
  static const sage = Color(0xFF627059);

  /// The "C".
  static const beige = Color(0xFFC9B39A);

  /// The logo's background.
  static const cream = Color(0xFFFBF8F2);
}

/// Builds the app's light and dark themes from [BrandColors].
///
/// Every color pairing used for text meets the WCAG contrast ratio of 4.5:1,
/// and every pairing used for controls such as switches meets 3:1. Sage on
/// the light background is 3.7:1, enough for filled elements (the add
/// buttons) but not for text, so accent text uses a slightly deeper sage.
abstract final class AppTheme {
  /// Light mode background: the logo's beige blended halfway to its cream.
  static const lightBackground = Color(0xFFE2D6C6);

  static ThemeData light() {
    const background = lightBackground;
    final colors =
        ColorScheme.fromSeed(
          seedColor: BrandColors.sage,
          brightness: Brightness.light,
        ).copyWith(
          // Background and text.
          surface: background,
          onSurface: BrandColors.navy, // 11.1:1.
          onSurfaceVariant: const Color(0xFF374145), // Softer navy, 7.3:1.
          outline: const Color(0xFF5B5F5C),
          outlineVariant: BrandColors.beige, // Dividers.
          // Cards, dialogs, menus and the navigation bar: the background
          // blended toward the logo's cream, so they stand out from it.
          surfaceContainerLowest: _blend(background, BrandColors.cream, 0.7),
          surfaceContainerLow: _blend(background, BrandColors.cream, 0.5),
          surfaceContainer: _blend(background, BrandColors.cream, 0.35),
          surfaceContainerHigh: _blend(background, BrandColors.cream, 0.25),
          surfaceContainerHighest: _blend(background, BrandColors.cream, 0.15),
          surfaceTint: Colors.transparent,
          // Accent: slightly deeper sage for text and controls (5.2:1).
          primary: const Color(0xFF4A594D),
          onPrimary: BrandColors.cream,
          // The logo's sage for filled elements such as the add buttons.
          primaryContainer: BrandColors.sage,
          onPrimaryContainer: BrandColors.cream,
          inversePrimary: _blend(BrandColors.sage, BrandColors.cream, 0.4),
          // Selected tab and selected segments: background tinted with sage.
          secondary: BrandColors.navy,
          onSecondary: BrandColors.cream,
          secondaryContainer: _blend(background, BrandColors.sage, 0.3),
          onSecondaryContainer: BrandColors.navy,
          // "Due soon" text.
          tertiary: const Color(0xFF5C3A12),
          onTertiary: BrandColors.cream,
          // "Overdue" text and destructive actions.
          error: const Color(0xFF7A1A16),
          onError: BrandColors.cream,
          // Snack bars.
          inverseSurface: BrandColors.navy,
          onInverseSurface: BrandColors.cream,
        );
    return _build(colors);
  }

  static ThemeData dark() {
    final colors =
        ColorScheme.fromSeed(
          seedColor: BrandColors.sage,
          brightness: Brightness.dark,
        ).copyWith(
          // Background and text.
          surface: BrandColors.navy,
          onSurface: BrandColors.cream,
          onSurfaceVariant: BrandColors.beige, // 7.9:1 on navy.
          outline: const Color(0xFF8E9AA0),
          outlineVariant: const Color(0xFF3B4A54),
          // Cards, dialogs, menus and the navigation bar: navy lightened slightly.
          surfaceContainerLowest: _blend(BrandColors.navy, Colors.black, 0.3),
          surfaceContainerLow: _blend(
            BrandColors.navy,
            BrandColors.cream,
            0.04,
          ),
          surfaceContainer: _blend(BrandColors.navy, BrandColors.cream, 0.07),
          surfaceContainerHigh: _blend(
            BrandColors.navy,
            BrandColors.cream,
            0.1,
          ),
          surfaceContainerHighest: _blend(
            BrandColors.navy,
            BrandColors.cream,
            0.14,
          ),
          surfaceTint: Colors.transparent,
          // Accent: lighter sage for text and controls (6.3:1 on navy).
          primary: _blend(BrandColors.sage, BrandColors.cream, 0.4),
          onPrimary: BrandColors.navy,
          // The logo's sage for filled elements such as the add buttons.
          primaryContainer: BrandColors.sage,
          onPrimaryContainer: BrandColors.cream,
          inversePrimary: const Color(0xFF3A4A44),
          // Selected tab and selected segments: navy tinted with sage.
          secondary: BrandColors.beige,
          onSecondary: BrandColors.navy,
          secondaryContainer: _blend(BrandColors.navy, BrandColors.sage, 0.45),
          onSecondaryContainer: BrandColors.cream,
          // "Due soon" text.
          tertiary: BrandColors.beige,
          onTertiary: BrandColors.navy,
          // Snack bars.
          inverseSurface: BrandColors.cream,
          onInverseSurface: BrandColors.navy,
        );
    return _build(colors);
  }

  static ThemeData _build(ColorScheme colors) {
    return ThemeData(
      colorScheme: colors,
      // Icons in list rows use the main text color rather than the softer one.
      listTileTheme: ListTileThemeData(iconColor: colors.onSurface),
      iconTheme: IconThemeData(color: colors.onSurface),
    );
  }

  static Color _blend(Color from, Color to, double amount) =>
      Color.lerp(from, to, amount)!;
}
