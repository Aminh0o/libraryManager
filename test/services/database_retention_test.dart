import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:library_manager/services/database_service.dart';

/// BR-05: retention must not let a same-day burst of writes rotate out every
/// older recovery point. The policy is a pure, clock-injectable function (fast,
/// exact) plus one real-file integration test that drives it through the actual
/// `createAutoBackup` path.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  group('selectBackupsToDelete policy (pure, BR-05)', () {
    final now = DateTime(2026, 9, 21, 12);
    BackupEntry e(String path, {int daysAgo = 0, int secondsAgo = 0}) =>
        BackupEntry(
          path,
          now.subtract(Duration(days: daysAgo, seconds: secondsAgo)),
        );

    test('nothing deleted while at or under keepCount', () {
      final backups = [for (var i = 0; i < 10; i++) e('b$i', secondsAgo: i)];
      expect(selectBackupsToDelete(backups, now: now), isEmpty);
    });

    test('same-day burst beyond keepCount drops the oldest', () {
      final backups = [for (var i = 0; i < 13; i++) e('b$i', secondsAgo: i)];
      final del = selectBackupsToDelete(backups, now: now);
      expect(del.length, 3);
      expect(del, containsAll(['b10', 'b11', 'b12']));
      expect(del, isNot(contains('b0')));
    });

    test('a same-day burst cannot rotate out an older daily backup', () {
      // 11 backups today + one 5 days ago (within horizon) + one 9 days ago
      // (outside it). Pure "keep last 10" would delete BOTH old files; the
      // daily floor must save the 5-day one.
      final backups = <BackupEntry>[
        for (var i = 0; i < 11; i++) e('today$i', secondsAgo: i),
        e('day5', daysAgo: 5),
        e('day9', daysAgo: 9),
      ];
      final del = selectBackupsToDelete(backups, now: now);
      expect(
        del,
        isNot(contains('day5')),
        reason: 'BR-05: the newest backup of a recent day is always kept',
      );
      expect(del, contains('day9'), reason: 'beyond the daily horizon');
      expect(del, contains('today10'), reason: 'the extra same-day one goes');
      expect(del.length, 2);
    });

    test('exactly one per recent day is kept even when many days are full', () {
      // Two backups on each of 3 recent days plus 12 today -> the older days'
      // newest must survive though they fall outside the newest 10.
      final backups = <BackupEntry>[
        for (var i = 0; i < 12; i++) e('today$i', secondsAgo: i),
        e('d2a', daysAgo: 2, secondsAgo: 0),
        e('d2b', daysAgo: 2, secondsAgo: 30),
        e('d4', daysAgo: 4),
      ];
      final del = selectBackupsToDelete(backups, now: now);
      expect(del, isNot(contains('d2a')), reason: 'day-2 newest kept');
      expect(del, isNot(contains('d4')), reason: 'day-4 kept');
      expect(
        del,
        contains('d2b'),
        reason: 'the redundant same-day older one goes',
      );
    });
  });

  group('createAutoBackup retention (real files, BR-05)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final svc = DatabaseService();
    late Directory tmp;
    late Directory backups;

    setUpAll(() async {
      tmp = Directory.systemTemp.createTempSync('lib_retain_');
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      await svc.database; // open production schema at the faked docs dir
    });

    tearDownAll(() async {
      final db = await svc.database;
      if (db.isOpen) await db.close();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    setUp(() {
      backups = Directory(p.join(tmp.path, 'library_backups'));
      if (backups.existsSync()) backups.deleteSync(recursive: true);
      backups.createSync(recursive: true);
    });

    File touch(String name, DateTime mtime) {
      final f = File(p.join(backups.path, name))..createSync();
      f.setLastModifiedSync(mtime);
      return f;
    }

    test(
      'an older daily backup survives a same-day burst through the real path',
      () async {
        final now = DateTime.now();
        final old = touch(
          'library_backup_old.db',
          now.subtract(const Duration(days: 5)),
        );
        // A burst of 11 "today" rotating backups: with the newest backup that
        // createAutoBackup is about to add, that is 12 today, pushing the old one
        // past a naive keep-last-10 cut.
        for (var i = 0; i < 11; i++) {
          touch(
            'library_backup_burst$i.db',
            now.subtract(Duration(seconds: i)),
          );
        }

        await svc.createAutoBackup();

        expect(
          old.existsSync(),
          isTrue,
          reason: 'BR-05: the 5-day-old daily point must not be rotated out',
        );
        final remaining = backups
            .listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('library_backup_'))
            .length;
        // keepCount(10) + one extra recent-day floor (the old one) == 11 kept.
        expect(remaining, 11);
      },
    );
  });
}
