import 'package:flutter/material.dart';

/// PHASE A -- centralized design tokens (frontend reconstruction).
///
/// The brief's rules 5/6/7/8/45 require ONE source of truth for spacing,
/// radius, typography, elevation and color that every screen CONSUMES, instead
/// of the 332+ scattered `Colors.*` / `fontSize: N` / `BorderRadius.circular(N)`
/// literals the audit of the old UI found. Nothing in `lib/screens` or
/// `lib/widgets` should hard-code a raw visual value once this system is in
/// place -- it reads tokens from here (or from [Theme.of] / the semantic color
/// extensions below), so a value can be changed in exactly one spot.
///
/// These are deliberately plain, const, and Flutter-only (no BuildContext) so
/// they are trivially unit-testable and can be referenced from `const` widget
/// constructors.
///
/// RTL (§40): every spacing helper here is DIRECTION-AGNOSTIC (symmetric or an
/// all-side value). Where an asymmetric inset is needed, screens must use
/// [EdgeInsetsDirectional] / `Padding(directional:)`, never `EdgeInsets` with a
/// positional left/right, so the layout mirrors correctly in Arabic.

/// A 4px-based spacing scale. Use these instead of arbitrary pixel paddings.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);
  static const EdgeInsets allXxl = EdgeInsets.all(xxl);

  /// Symmetric vertical/horizontal padding (direction-agnostic, RTL-safe).
  static EdgeInsets v(double y, [double x = 0]) =>
      EdgeInsets.symmetric(vertical: y, horizontal: x);
}

/// Corner radii. Kept modest on purpose (§7/§55): this is desktop software, not
/// a pile of floating mobile cards. The old 20px card radius is retired.
abstract final class AppRadius {
  static const double none = 0;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius field = BorderRadius.all(Radius.circular(md));
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(md));
  static const BorderRadius tile = BorderRadius.all(Radius.circular(md));
}

/// Icon sizes -- one ladder so glyphs stop drifting between 18/20/22/28/32.
abstract final class AppIcon {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double empty = 48;
  static const double hero = 64;
}

/// Motion durations (§37): fast, subtle, purposeful. No decorative animation.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration enter = Duration(milliseconds: 220);
  static const Duration exit = Duration(milliseconds: 160);
  static const Duration toast = Duration(milliseconds: 200);
}

/// Fixed layout dimensions for the shell + responsive ceilings (§10/§38).
abstract final class AppSizing {
  static const double railExpanded = 236;
  static const double railCollapsed = 72;
  static const double topBarHeight = 64;
  static const double minWindowWidth = 720;
  static const double minWindowHeight = 480;

  /// Content is centered and width-capped so a maximized ultrawide window does
  /// not stretch forms/tables to unreadable line lengths (§38).
  static const double maxContentWidth = 1280;

  /// Every `AlertDialog` / `ConfirmActionDialog` in the app is wrapped in a
  /// `ConstrainedBox(maxWidth: maxDialogWidth)`. Without this, Flutter's
  /// default dialog sizing makes short dialogs pinch their fields (label
  /// ellipsis, dropdown menus overflowing) and lets long dialogs span the
  /// whole monitor. 560 dp is a comfortable measure for a two-column form
  /// and fits every M3 breakpoint we ship.
  static const double maxDialogWidth = 560;
  static const double maxFormWidth = 720;

  /// Breakpoint below which the rail collapses to icons-only.
  static const double compactWidth = 960;
}

/// A single border width for all hairline strokes (dividers, outlined fields).
abstract final class AppBorder {
  static const double width = 1;
}

/// Semantic status palette (§26/§27). Colors are centralized here so a status
/// means the same thing everywhere, and are chosen to stay legible on BOTH light
/// and dark surfaces (rendered as a tinted chip with text, never color alone).
/// This is a bounded, MEANING-BEARING use of color -- not decoration.
abstract final class AppStatus {
  static const Color available = Color(0xFF2E7D32); // green  : disponible
  static const Color borrowed = Color(0xFF1565C0); // blue   : emprunté
  static const Color reserved = Color(0xFFEF6C00); // orange : réservé
  static const Color damaged = Color(0xFFC62828); // red    : endommagé
  static const Color repair = Color(0xFFAD1457); // magenta : en réparation
  static const Color lost = Color(0xFF5D4037); // brown    : perdu
  static const Color archived = Color(0xFF546E7A); // blue-grey: archivé
  static const Color neutral = Color(0xFF757575); // grey     : legacy/unknown

  /// State colors used by the connection indicator + operational badges.
  static const Color success = available;
  static const Color warning = Color(0xFFB26A00);
  static const Color danger = Color(0xFFC62828);
  static const Color info = Color(0xFF1565C0);
}

/// Convenience access to semantic colors from a [BuildContext], resolved once so
/// screens never reach for raw `Colors.green` etc. `success/danger` adapt to
/// brightness; the fixed [AppStatus] hues are used as tinted chip foregrounds
/// that read on both surfaces.
extension AppSemanticColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  Color get successColor => colors.primary;
  Color get warningColor => AppStatus.warning;
  Color get dangerColor => Theme.of(this).colorScheme.error;
  Color get infoColor => AppStatus.info;

  /// A muted, brightness-correct "secondary text" color (replaces the old
  /// hard-coded Colors.grey[600] everywhere).
  Color get mutedText => colors.onSurfaceVariant;
}
