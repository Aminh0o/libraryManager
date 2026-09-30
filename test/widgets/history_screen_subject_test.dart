import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/history_screen.dart';
import 'package:library_manager/services/repository.dart';

/// Pass 5: `HistoryScreen(initialSubject: ...)` opens with the subject field
/// already populated AND the very first repo call carries that subject -- a
/// screen that renders a pre-filled text field but queries unfiltered would
/// be a false-positive UX (the operator sees one row of BK-42 mixed with
/// every other record and trusts the chrome). Both halves are pinned here.
class _Repo implements LibraryRepository {
  final List<String?> subjectsSeen = [];

  @override
  Future<List<Map<String, dynamic>>> getHistory({
    int limit = 20,
    int offset = 0,
    String? subject,
  }) async {
    subjectsSeen.add(subject);
    return const [];
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

void main() {
  testWidgets('initialSubject pre-fills the field and the first query',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    final provider = LibraryProvider.forTesting(repository: repo, isHost: true);
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryProvider>.value(
        value: provider,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HistoryScreen(initialSubject: 'BK-42'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Field state.
    final field = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(
      field.controller?.text,
      'BK-42',
      reason: 'the search field must visibly reflect the initial subject',
    );
    // Query state.
    expect(
      repo.subjectsSeen.first,
      'BK-42',
      reason: 'the first repo call must carry the subject, not null',
    );
  });
}
