import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// PHASE A -- the single theme factory (frontend reconstruction).
///
/// Every visual decision that used to be pasted per-screen (card shape, field
/// outline, button corner, dialog radius, divider weight, text colour) now
/// lives here once, so light and dark are BOTH designed rather than the old
/// light-only UI with hard-coded `Colors.white`/`Colors.black87` that rendered
/// an unreadable white slab in dark mode. Themes are derived from the operator's
/// configurable seed ([AppearanceController]) so the "white-label" primary colour
/// finally reaches the chrome instead of being overridden by `Colors.orange`.
///
/// Deliberately free of `google_fonts` (which lazily fetches over the network and
/// is hostile to a pure test binding): [AppearanceController] layers the
/// established "Outfit" family on top of the scale produced here.
class AppTheme {
  const AppTheme._();

  static ThemeData light(Color seed) => _build(seed, Brightness.light);
  static ThemeData dark(Color seed) => _build(seed, Brightness.dark);

  static ThemeData _build(Color seed, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    final textTheme = _normalizeText(base.textTheme, scheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      // M3 tints elevated surfaces with the primary hue; that tonal noise reads
      // as "AI dashboard". Flatten it so surfaces stay calm neutral (§43/§55).
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      dividerTheme: const DividerThemeData(
        thickness: AppBorder.width,
        space: AppBorder.width,
        color: null, // inherit scheme.outlineVariant
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: scheme.outlineVariant,
            width: AppBorder.width,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        border: _outline(scheme.outlineVariant),
        enabledBorder: _outline(scheme.outlineVariant),
        focusedBorder: _outline(scheme.primary, width: 1.6),
        errorBorder: _outline(scheme.error),
        focusedErrorBorder: _outline(scheme.error, width: 1.6),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),
      navigationRailTheme: NavigationRailThemeData(
        // Seed-derived, brightness-correct rail -- replaces the old hard-coded
        // Colors.brown[50] that both ignored the seed and stayed light in dark mode.
        backgroundColor: isDark ? scheme.surfaceContainerLow : scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.surfaceContainer,
          foregroundColor: scheme.onSurface,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          minimumSize: const Size(0, 40),
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        // A flat `foregroundColor` here would override Material 3's
        // disabled-state resolution and make `onPressed: null` buttons look
        // identical to enabled ones (defeats the queue-reorder boundary
        // affordance, see Pass 6 / reservations_screen `_tileTrailing`).
        // Resolve explicitly so a disabled IconButton dims to 38% onSurface
        // like every other M3 icon button.
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            return scheme.onSurfaceVariant;
          }),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        iconColor: null,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.chip),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // Seed-derived (was a literal Colors.orange) and legible in both modes.
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? scheme.surfaceContainerHighest
            : const Color(0xFF323232),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? scheme.onSurface : Colors.white,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.tile),
        width: 420,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.tile,
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  static OutlineInputBorder _outline(
    Color color, {
    double width = AppBorder.width,
  }) => OutlineInputBorder(
    borderRadius: AppRadius.field,
    borderSide: BorderSide(color: color, width: width),
  );

  /// Nudge the M3 default scale into the app's controlled roles: page titles
  /// semibold, a readable desktop body size, tightened labels. Everything keeps
  /// the platform weights; only the roles screens rely on are pinned here so a
  /// screen just asks for `textTheme.headlineSmall` and gets the token.
  static TextTheme _normalizeText(TextTheme t, ColorScheme s) {
    return t.copyWith(
      headlineSmall: t.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: s.onSurface,
      ),
      titleLarge: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: s.onSurface,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: s.onSurface,
      ),
      bodyLarge: t.bodyLarge?.copyWith(height: 1.4, color: s.onSurface),
      bodyMedium: t.bodyMedium?.copyWith(height: 1.4, color: s.onSurface),
      bodySmall: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
    );
  }
}

/// Named text roles (§5) so screens stop inventing `fontSize: 17`. Each maps to
/// the centralized scale in [AppTheme]; call sites get color/size/weight in one
/// semantic read of the theme.
extension AppTypography on BuildContext {
  TextStyle? get pageTitle => text.headlineSmall;
  TextStyle? get sectionTitle => text.titleMedium;
  TextStyle? get body => text.bodyMedium;
  TextStyle? get bodyMuted => text.bodySmall;
  TextStyle? get label => text.labelLarge;
  TextStyle? get caption => text.bodySmall;

  /// A large metric figure (dashboards, stat tiles).
  TextStyle get metric =>
      text.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colors.onSurface,
      ) ??
      const TextStyle(fontSize: 28, fontWeight: FontWeight.bold);
}
