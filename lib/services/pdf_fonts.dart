import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Shared PDF print typography (DEF-04 — Arabic printing).
///
/// The `pdf` package only performs Arabic shaping (joining forms + bidi
/// ordering) inside `TtfFont.drawString`; its built-in Base-14 Helvetica
/// face has no Arabic glyphs and no shaping, so every slip/report built
/// with the default theme printed Arabic member names, titles and labels
/// as garbage. That was previously a *disclosed limitation*; the owner
/// reports it as a defect to fix, so both document builders now pull a
/// real Unicode face from here by default.
///
/// The bundled face is **IBM Plex Sans Arabic** (SIL OFL 1.1, taken from
/// the official `google/fonts` repository; `assets/fonts/OFL.txt` ships
/// beside it) — one family that covers Latin-1 accents *and* Arabic, so
/// EN / FR / AR documents all render in a consistent style.
///
/// The bytes loader is injectable: production reads through
/// [rootBundle] (the asset bundle compiled into the installer), unit and
/// widget tests can read the same files straight from disk, and a
/// genuinely missing/broken asset degrades to the old Helvetica behaviour
/// instead of failing the whole print — printing a degraded document is
/// recoverable, throwing at the print button is not.
class PdfPrintFonts {
  PdfPrintFonts._();

  static const String regularAsset =
      'assets/fonts/IBMPlexSansArabic-Regular.ttf';
  static const String boldAsset = 'assets/fonts/IBMPlexSansArabic-Bold.ttf';

  /// Asset key for the OFL licence text, kept in the bundle for attribution.
  static const String licenceAsset = 'assets/fonts/OFL.txt';

  static pw.ThemeData? _cachedTheme;

  /// The raw TTF bytes, or `null` when they cannot be read. Plain
  /// `ByteData` crosses an `Isolate.run` boundary, so a root-isolate caller
  /// (the report export worker) loads here and hands the result to a
  /// spawned isolate, which must NOT touch [rootBundle] itself.
  static Future<({ByteData regular, ByteData bold})?> bytes({
    Future<ByteData> Function(String key)? loader,
  }) async {
    final read = loader ?? rootBundle.load;
    try {
      return (regular: await read(regularAsset), bold: await read(boldAsset));
    } catch (e) {
      // See [theme]: a missing print font degrades, it never blocks.
      debugPrint('PdfPrintFonts: font bytes unavailable ($e)');
      return null;
    }
  }

  /// Loads (once) and returns the print theme, or `null` when the faces
  /// cannot be read — callers pass the result straight to
  /// `pw.Document(theme:)`, where `null` means "keep the defaults".
  static Future<pw.ThemeData?> theme({
    Future<ByteData> Function(String key)? loader,
  }) async {
    if (_cachedTheme != null && loader == null) return _cachedTheme;
    final pair = await bytes(loader: loader);
    if (pair == null) return null;
    final data = themeFromBytes(pair.regular, pair.bold);
    if (loader == null) _cachedTheme = data;
    return data;
  }

  /// Builds the theme from raw TTF bytes — the testable seam that keeps
  /// this service free of any bundle dependency.
  static pw.ThemeData themeFromBytes(ByteData regular, ByteData bold) {
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
  }

  /// Disk-path variant used by pure-Dart tests (no widget binding, hence
  /// no asset bundle). Same files, same bytes as the bundled assets.
  static Future<ByteData> loadFromFile(String assetKey) async {
    final bytes = await File(assetKey).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  @visibleForTesting
  static void clearCacheForTesting() => _cachedTheme = null;
}
