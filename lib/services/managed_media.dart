import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Phase 5/6 (schema v24): managed storage for member photos and book covers.
///
/// The branding logo set the pattern (`Settings > Appearance` copies the picked
/// image into `Documents/branding/` so the header survives the user moving or
/// deleting the original file). This service generalizes that to per-record
/// images: the DB stores the path of the COPY under the app's documents
/// folder, never the raw picker path, so an image vanishing from Downloads can
/// never blank a member card or a book detail page.
///
/// Rules inherited from the logo flow and the update downloader:
/// * a hard size cap (rejects camera dumps before they bloat backups);
/// * extension allow-list (png/jpg/jpeg only — no arbitrary files);
/// * deletion of the managed copy is best-effort and never throws: an orphan
///   file is a leak, not a failure the operator must be screamed at for.
class ManagedMedia {
  ManagedMedia._();

  /// Images larger than this are refused (same 2 MB ceiling the logo uses;
  /// photos/covers are displayed at <= a few hundred px, so anything above is
  /// a raw camera dump that would only bloat every backup).
  static const int maxBytes = 2 * 1024 * 1024;

  /// Bare lowercase extensions WITHOUT the leading dot (`.jpg` -> `jpg`):
  /// `path.extension` returns the dotted form, comparing raw values against
  /// this set silently rejects every legitimate image.
  static const Set<String> _allowedExtensions = {'png', 'jpg', 'jpeg'};

  static String _bareExtension(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext.startsWith('.') ? ext.substring(1) : ext;
  }

  /// Copies [sourcePath] into `Documents/<folder>/<fileName><ext>` and returns
  /// the absolute path of the managed copy. Throws [MediaException] (typed,
  /// so the UI can toast a localized message) when the file is missing, of a
  /// disallowed type, or over the size cap.
  ///
  /// [folder] is a safe lowercase identifier ('members', 'covers'); it is
  /// validated, never taken from user text.
  static Future<String> importImage({
    required String sourcePath,
    required String folder,
    required String fileName,
  }) async {
    if (!RegExp(r'^[a-z_]+$').hasMatch(folder)) {
      throw MediaException('unsafe folder name: $folder');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(fileName)) {
      throw MediaException('unsafe file name: $fileName');
    }
    final ext = _bareExtension(sourcePath);
    if (!_allowedExtensions.contains(ext)) {
      throw MediaException('unsupported image type: $ext');
    }
    final File src;
    try {
      src = File(sourcePath);
      final length = await src.length();
      if (length == 0 || length > maxBytes) {
        throw MediaException('image size invalid: $length bytes');
      }
    } on MediaException {
      rethrow;
    } catch (e) {
      throw MediaException('cannot read source image: $e');
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Fixed managed name (not the original): a renamed/re-saved source can
    // never pile up copies, and path characters from the source are irrelevant.
    final dest = File(p.join(dir.path, '$fileName.$ext'));
    // A different format chosen later must replace, not coexist with, the old
    // managed image (jpg saved next to a stale png would leave the detail
    // page pointing at whichever path the DB still holds — clean both).
    for (final stale in _allowedExtensions) {
      if (stale == ext) continue;
      try {
        final f = File(p.join(dir.path, '$fileName.$stale'));
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('ManagedMedia: stale $fileName.$stale cleanup skipped: $e');
      }
    }
    await src.copy(dest.path);
    return dest.path;
  }

  /// Best-effort removal of a managed image. Only deletes files inside the
  /// app's own media folders — a tampered/foreign DB path is ignored rather
  /// than followed. Never throws.
  static Future<void> removeImage(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final normalized = p.normalize(path);
      final roots = [
        p.join(docs.path, 'members'),
        p.join(docs.path, 'covers'),
        p.join(docs.path, 'branding'),
      ];
      if (!roots.any(
        (r) => normalized.startsWith(p.normalize(r) + p.separator),
      )) {
        return; // not a managed media path: never delete foreign files
      }
      final f = File(normalized);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('ManagedMedia: removeImage($path) skipped: $e');
    }
  }
}

/// Typed rejection from [ManagedMedia] so callers can surface an honest
/// localized toast instead of a raw filesystem error.
class MediaException implements Exception {
  MediaException(this.message);
  final String message;

  @override
  String toString() => 'MediaException: $message';
}
