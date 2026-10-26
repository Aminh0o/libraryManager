import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:library_manager/services/managed_media.dart';

/// Phase 5/6: the managed media store is the trust boundary between "some
/// file the user picked" and "an image the app owns and backs up". These run
/// against a REAL temp directory through the path_provider platform seam:
/// import copies (never moves), rejects oversized/foreign-type files, replaces
/// a stale-format copy, and removeImage refuses to delete anything outside the
/// app's own media folders.
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory sourceDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('managed_media_test');
    PathProviderPlatform.instance = _TempPathProvider(tmp.path);
    sourceDir = await Directory(p.join(tmp.path, 'src')).create();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> makeSource(String name, int bytes) async {
    final f = File(p.join(sourceDir.path, name));
    await f.writeAsBytes(List.filled(bytes, 7));
    return f;
  }

  test('import copies into Documents/<folder>/<fileName><ext>', () async {
    final src = await makeSource('holiday.png', 128);
    final dest = await ManagedMedia.importImage(
      sourcePath: src.path,
      folder: 'members',
      fileName: 'AA0100',
    );
    expect(dest, p.join(tmp.path, 'members', 'AA0100.png'));
    expect(await File(dest).exists(), isTrue);
    // The SOURCE survives: the DB points at the copy, the user's file is
    // theirs to move/delete afterwards.
    expect(await src.exists(), isTrue);
  });

  test('a jpg replace deletes the stale png copy of the same record', () async {
    final png = await makeSource('a.png', 64);
    final first = await ManagedMedia.importImage(
      sourcePath: png.path,
      folder: 'members',
      fileName: 'M1',
    );
    expect(await File(first).exists(), isTrue);

    final jpg = await makeSource('b.jpg', 64);
    final second = await ManagedMedia.importImage(
      sourcePath: jpg.path,
      folder: 'members',
      fileName: 'M1',
    );
    expect(second.endsWith('M1.jpg'), isTrue);
    expect(await File(first).exists(), isFalse, reason: 'stale png must go');
  });

  test('rejects empty, oversized, foreign-type and path-y inputs', () async {
    final empty = await makeSource('e.png', 0);
    expect(
      () => ManagedMedia.importImage(
        sourcePath: empty.path,
        folder: 'members',
        fileName: 'M1',
      ),
      throwsA(isA<MediaException>()),
    );

    final huge = await makeSource(
      'h.png',
      ManagedMedia.maxBytes + 1,
    ); // sparse-ish: writeAsBytes of 2MB+1 zeros is fine in temp
    expect(
      () => ManagedMedia.importImage(
        sourcePath: huge.path,
        folder: 'members',
        fileName: 'M2',
      ),
      throwsA(isA<MediaException>()),
    );

    final exe = await makeSource('evil.exe', 32);
    expect(
      () => ManagedMedia.importImage(
        sourcePath: exe.path,
        folder: 'members',
        fileName: 'M3',
      ),
      throwsA(isA<MediaException>()),
    );

    // Unsafe folder / file names are refused before any filesystem touch.
    expect(
      () => ManagedMedia.importImage(
        sourcePath: exe.path,
        folder: '../evil',
        fileName: 'M4',
      ),
      throwsA(isA<MediaException>()),
    );
    expect(
      () => ManagedMedia.importImage(
        sourcePath: exe.path,
        folder: 'members',
        fileName: r'..\escape',
      ),
      throwsA(isA<MediaException>()),
    );
  });

  test('removeImage deletes managed files, ignores foreign paths', () async {
    final src = await makeSource('x.jpg', 64);
    final managed = await ManagedMedia.importImage(
      sourcePath: src.path,
      folder: 'covers',
      fileName: '0500',
    );
    await ManagedMedia.removeImage(managed);
    expect(await File(managed).exists(), isFalse);

    // A tampered DB value pointing OUTSIDE the media folders is never deleted.
    final foreign = File(p.join(sourceDir.path, 'keep.jpg'));
    await foreign.writeAsBytes([1, 2, 3]);
    await ManagedMedia.removeImage(foreign.path);
    expect(await foreign.exists(), isTrue);

    // Null/blank/missing are no-ops, never throws.
    await ManagedMedia.removeImage(null);
    await ManagedMedia.removeImage('');
    await ManagedMedia.removeImage(p.join(tmp.path, 'members', 'ghost.png'));
  });
}
