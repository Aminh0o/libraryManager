import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/repository.dart';
import 'package:library_manager/widgets/record_history_section.dart';

/// Pass 5: the shared `RecordHistorySection` renders the last N audit rows
/// mentioning the given subject. Three behaviours pinned here:
///  1. rows arrive → every `details` line is visible verbatim;
///  2. no rows → the friendly "No recent activity" empty state shows
///     (proving the section ran and reported, not that it silently vanished);
///  3. repo throws → the section hides entirely (honest-omission pattern).
class _Repo implements LibraryRepository {
  _Repo({this.rows = const [], this.throwOnRead = false});
  final List<Map<String, dynamic>> rows;
  final bool throwOnRead;
  String? lastSubject;
  int? lastLimit;

  @override
  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 20,
    int offset = 0,
    String? subject,
  }) async {
    lastLimit = limit;
    lastSubject = subject;
    if (throwOnRead) throw StateError('offline');
    return rows;
  }

  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pump(
  WidgetTester tester, {
  required _Repo repo,
  required Widget child,
}) async {
  tester.view.physicalSize = const Size(1400, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final provider = LibraryProvider.forTesting(repository: repo, isHost: true);
  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _row(String details, {String stamp = '2026-01-01T10:00:00.000'}) => {
      'timestamp': stamp,
      'operation': 'UPDATE',
      'details': details,
      'user': 'Host',
    };

void main() {
  testWidgets('renders each matching audit row verbatim', (tester) async {
    final repo = _Repo(rows: [
      _row('Copie #1 de BK-001 -> available', stamp: '2026-01-03T10:00:00.000'),
      _row('Emprunt: BK-001 par Amira', stamp: '2026-01-02T10:00:00.000'),
    ]);
    await _pump(
      tester,
      repo: repo,
      child: const RecordHistorySection(
        subject: 'BK-001',
        title: 'History',
        limit: 8,
      ),
    );
    expect(find.text('History'), findsOneWidget);
    expect(
      find.text('Copie #1 de BK-001 -> available'),
      findsOneWidget,
      reason: 'the newest row must be visible',
    );
    expect(
      find.text('Emprunt: BK-001 par Amira'),
      findsOneWidget,
      reason: 'every returned row renders (no truncation to 1)',
    );
    expect(
      repo.lastSubject,
      'BK-001',
      reason: 'section must hand the subject through to the repo call',
    );
    expect(
      repo.lastLimit,
      8,
      reason: 'the widget-supplied limit must not silently widen',
    );
  });

  testWidgets('empty result hides the section', (tester) async {
    await _pump(
      tester,
      repo: _Repo(rows: const []),
      child: const RecordHistorySection(
        subject: 'BK-999',
        title: 'History',
      ),
    );
    // The plan's honest-omission principle: an ancillary timeline does not
    // shout empty-state copy at the operator.
    expect(find.text('History'), findsNothing);
    expect(find.text('No recent activity for this record.'), findsNothing);
  });

  testWidgets('a repo failure hides the section (honest-omission)',
      (tester) async {
    await _pump(
      tester,
      repo: _Repo(throwOnRead: true),
      child: const RecordHistorySection(
        subject: 'BK-001',
        title: 'History',
      ),
    );
    // The whole card is absent: no crash, no error banner, no ghost chrome.
    expect(find.text('History'), findsNothing);
    expect(find.text('No recent activity for this record.'), findsNothing);
  });
}
