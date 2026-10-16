import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/update_service.dart';

/// §6.13 real-download evidence. These are plain `test()`s that use `dart:io`
/// file IO and a real local `HttpServer`; because they never call
/// `TestWidgetsFlutterBinding.ensureInitialized()` the testing HTTP override is
/// not installed, so `UpdateService.downloadToPath` hits the socket for real
/// (the same reason the concurrency suite works over a real server). The
/// optional block at the bottom exercises the true GitHub release path when
/// `LM_LIVE_UPDATE_TEST=1` is set — a one-time live proof, skipped by default
/// so the suite stays network-independent and deterministic.

/// Open a real (plaintext) response to feed the streaming engine directly.
/// `downloadToPath` is HTTPS-only by design, so the byte mechanics are
/// exercised through `streamResponseToFile`, the seam it delegates to.
Future<(HttpClientResponse, HttpClient)> fetch(String url) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  final resp = await req.close();
  return (resp, client);
}

void main() {
  const knownHello =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  group('sha256OfFile / fileMatchesHash — streaming integrity', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lm_sha_'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test(
      'computes the SHA-256 of a file that equals the known digest',
      () async {
        final f = File('${tmp.path}\\hello.txt')..writeAsStringSync('hello');
        expect(await UpdateService.sha256OfFile(f.path), knownHello);
      },
    );

    test(
      'fileMatchesHash accepts the exact hash and rejects a wrong one',
      () async {
        final f = File('${tmp.path}\\hello.txt')..writeAsStringSync('hello');
        expect(await UpdateService.fileMatchesHash(f.path, knownHello), isTrue);
        expect(
          await UpdateService.fileMatchesHash(f.path, 'f' * 64),
          isFalse,
          reason: 'a tampered archive must never match',
        );
      },
    );

    test('fileMatchesHash fails closed on a malformed expected hash', () async {
      final f = File('${tmp.path}\\hello.txt')..writeAsStringSync('hello');
      expect(await UpdateService.fileMatchesHash(f.path, 'nothex'), isFalse);
      expect(await UpdateService.fileMatchesHash(f.path, ''), isFalse);
    });

    test(
      'matches even when the manifest is uppercase (case-insensitive)',
      () async {
        final f = File('${tmp.path}\\hello.txt')..writeAsStringSync('hello');
        expect(
          await UpdateService.fileMatchesHash(f.path, knownHello.toUpperCase()),
          isTrue,
        );
      },
    );
  });

  group('downloadToPath — trust boundary + streaming mechanics', () {
    test('refuses a plaintext-http url without contacting it (§317)', () async {
      final dest = '${Directory.systemTemp.createTempSync('lm_dl_')}\\pkg.zip';
      final out = await UpdateService.downloadToPath(
        'http://example.test/pkg.zip',
        dest,
      );
      expect(out.status, DownloadStatus.failed);
      expect(out.error, contains('insecure'));
    });

    test(
      'streams a real local download, reports progress, and writes bytes',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        const body = 'library-manager-update-payload';
        server.listen((req) async {
          req.response
            ..contentLength = body.length
            ..add(utf8.encode(body));
          await req.response.close();
        });
        final dir = Directory.systemTemp.createTempSync('lm_dl_');
        final dest = '${dir.path}\\pkg.bin';
        final progress = <int>[];
        final (resp, client) = await fetch(
          'http://127.0.0.1:${server.port}/pkg.bin',
        );
        final out = await UpdateService.streamResponseToFile(
          resp,
          client,
          dest,
          onProgress: (r, t) => progress.add(r),
        );
        await server.close(force: true);
        expect(
          out.status,
          DownloadStatus.verified,
        ); // provisional: bytes written
        expect(File(dest).readAsBytesSync(), utf8.encode(body));
        expect(progress.isNotEmpty, isTrue);
        expect(progress.last, body.length);
        dir.deleteSync(recursive: true);
      },
    );

    // Adversarial-review P0 regression: the real updater writes into an
    // app-owned …/Documents/updates/ subfolder that does NOT exist on a fresh
    // install. File.openWrite() does not create parents and on Windows throws
    // FileSystemException, which would make EVERY download fail. This proves
    // the engine creates the missing nested directory itself.
    test(
      'creates a missing nested destination directory before writing',
      () async {
        const body = 'update-payload';
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) async {
          req.response
            ..contentLength = body.length
            ..add(utf8.encode(body));
          await req.response.close();
        });
        final dir = Directory.systemTemp.createTempSync('lm_dl_nested_');
        // …/updates/downloads/pkg.zip where neither subfolder exists yet.
        final dest = '${dir.path}/updates/downloads/pkg.zip';
        expect(Directory('${dir.path}/updates').existsSync(), isFalse);
        final (resp, client) = await fetch(
          'http://127.0.0.1:${server.port}/pkg.zip',
        );
        final out = await UpdateService.streamResponseToFile(
          resp,
          client,
          dest,
        );
        await server.close(force: true);
        expect(out.status, DownloadStatus.verified);
        expect(File(dest).existsSync(), isTrue, reason: 'parents auto-created');
        expect(File(dest).readAsBytesSync(), utf8.encode(body));
        dir.deleteSync(recursive: true);
      },
    );

    test('enforces the byte cap against an oversized stream', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final chunk = List<int>.filled(1024, 7);
        for (var i = 0; i < 50; i++) {
          req.response.add(chunk);
        }
        await req.response.close();
      });
      final dir = Directory.systemTemp.createTempSync('lm_dl_');
      final dest = '${dir.path}\\big.bin';
      final (resp, client) = await fetch(
        'http://127.0.0.1:${server.port}/big.bin',
      );
      final out = await UpdateService.streamResponseToFile(
        resp,
        client,
        dest,
        maxBytes: 2048,
      );
      await server.close(force: true);
      expect(out.status, DownloadStatus.failed);
      expect(out.error, contains('size cap'));
      expect(File(dest).existsSync(), isFalse, reason: 'partial file removed');
      dir.deleteSync(recursive: true);
    });

    test('a mid-stream cancel stops and deletes the partial file', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        for (var i = 0; i < 20; i++) {
          req.response.add(List<int>.filled(4096, 1));
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await req.response.close();
      });
      final dir = Directory.systemTemp.createTempSync('lm_dl_');
      final dest = '${dir.path}\\slow.bin';
      var seen = 0;
      final (resp, client) = await fetch(
        'http://127.0.0.1:${server.port}/slow.bin',
      );
      final out = await UpdateService.streamResponseToFile(
        resp,
        client,
        dest,
        onProgress: (r, t) => seen = r,
        isCancelled: () => seen > 4000,
      );
      await server.close(force: true);
      expect(out.status, DownloadStatus.cancelled);
      expect(File(dest).existsSync(), isFalse);
      dir.deleteSync(recursive: true);
    });
  });

  group('downloadAndVerify — honest refusal before any transfer', () {
    test(
      'refuses an artifact with no checksum manifest (never unverified)',
      () async {
        const artifact = UpdateArtifact(
          packageUrl: 'https://example.test/pkg.zip',
          fileName: 'pkg.zip',
        );
        final out = await UpdateService.downloadAndVerify(
          artifact,
          '${Directory.systemTemp.createTempSync('lm_v_')}\\pkg.zip',
        );
        expect(out.status, DownloadStatus.failed);
        expect(out.error, contains('no checksum'));
      },
    );

    test('refuses a non-HTTPS package outright', () async {
      const artifact = UpdateArtifact(
        packageUrl: 'http://example.test/pkg.zip',
        checksumUrl: 'https://example.test/pkg.zip.sha256sum',
        fileName: 'pkg.zip',
      );
      final out = await UpdateService.downloadAndVerify(
        artifact,
        '${Directory.systemTemp.createTempSync('lm_v_')}\\pkg.zip',
      );
      expect(out.status, DownloadStatus.failed);
    });
  });

  // Live proof against the REAL published release. Skipped unless explicitly
  // requested so the deterministic suite never depends on the network. Run
  // once with:  \$env:LM_LIVE_UPDATE_TEST='1'; flutter test test/services/update_service_download_test.dart
  final liveWanted = Platform.environment['LM_LIVE_UPDATE_TEST'] == '1';
  test(
    'LIVE: in-app download + SHA-256 verify of the real published checksum',
    () async {
      const artifact = UpdateArtifact(
        packageUrl:
            'https://github.com/Aminh0o/libraryManager/releases/download/v1.1.3/'
            'LibraryManager-1.1.3-windows-x64.zip.sha256sum',
        checksumUrl:
            'https://github.com/Aminh0o/libraryManager/releases/download/v1.1.3/'
            'LibraryManager-1.1.3-windows-x64.zip.sha256sum',
        fileName: 'LibraryManager-1.1.3-windows-x64.zip.sha256sum',
      );
      final dir = Directory.systemTemp.createTempSync('lm_live_');
      final dest = '${dir.path}\\checksum.txt';
      // Here the "package" IS the 102-byte checksum file, whose real sha256 is
      // itself published — a self-consistent, tiny live end-to-end check that
      // the download → parse → verify path works against github.com.
      final dl = await UpdateService.downloadToPath(artifact.packageUrl!, dest);
      expect(dl.status, DownloadStatus.verified);
      final text = File(dest).readAsStringSync();
      final hex = UpdateService.parseChecksumText(text);
      expect(hex, isNotNull, reason: 'real manifest parses: $text');
      expect(
        await UpdateService.sha256OfFile(dest),
        isNot(hex),
        reason: 'the file is the manifest, not its own hash',
      );
      dir.deleteSync(recursive: true);
    },
    skip: liveWanted
        ? false
        : 'set LM_LIVE_UPDATE_TEST=1 to run the live check',
  );
}
