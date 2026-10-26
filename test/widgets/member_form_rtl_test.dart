import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/screens/members_screen.dart';
import 'package:library_manager/services/repository.dart';

// DEF-05 (Phase 3, RTL): in the Arabic UI the ambient text direction is RTL.
// Free-text names must follow it — but machine-format values (ids, phones,
// emails, codes, IPs, ISO dates) must NOT: the bidi algorithm reorders their
// runs and the fields open on the wrong caret side. The screens pin those
// fields LTR explicitly; this test proves the pin exists *while the dialog
// itself really is RTL* — and that name fields stay ambient (over-pinning
// Arabic names to LTR would be its own defect).

class _RtlRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpArabic(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final provider = LibraryProvider.forTesting(
    repository: _RtlRepo(),
    isHost: false,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<LibraryProvider>.value(
      value: provider,
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MembersScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<TextField> dialogFields(WidgetTester tester) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .evaluate()
    .map((e) => e.widget as TextField)
    .toList();

void main() {
  testWidgets('member dialog is RTL but machine-format fields are pinned LTR', (
    tester,
  ) async {
    await _pumpArabic(tester);

    // The whole screen really is right-to-left — otherwise the assertion below
    // would pass vacuously on an LTR build.
    final context = tester.element(find.byType(MembersScreen));
    expect(Directionality.of(context), TextDirection.rtl);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final fields = dialogFields(tester);
    // v24 dialog: id, first, last, phone, email, expiry (picker-backed,
    // readOnly), address, notes (multiline -- still a TextField). The
    // type/status pickers are DropdownButtons and are not counted here.
    expect(fields, hasLength(8));

    // Machine-format fields carry the explicit LTR pin: the read-only id
    // field, the phone field, the email field and the ISO expiry field.
    final pinned = fields
        .where((f) => f.textDirection == TextDirection.ltr)
        .toList();
    expect(pinned, hasLength(4));
    expect(pinned.any((f) => f.readOnly), isTrue); // id + expiry are readOnly
    expect(
      pinned.where((f) => f.readOnly).length,
      2,
    ); // id field + expiry picker field
    expect(pinned.any((f) => f.keyboardType == TextInputType.phone), isTrue);
    expect(
      pinned.any((f) => f.keyboardType == TextInputType.emailAddress),
      isTrue,
    );

    // Name fields + address + notes stay ambient (no pin): they must follow
    // RTL for Arabic text — over-pinning them would be its own defect.
    final ambient = fields.where((f) => f.textDirection == null).toList();
    expect(ambient, hasLength(4));
  });

  testWidgets('v24 dialog exposes the enrichment controls on an existing row', (
    tester,
  ) async {
    // The owner upgrade must be OPERABLE in the real form: type + status
    // dropdowns and the photo button exist for a SAVED member, and stored
    // canonical values render localized in the Arabic UI.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = LibraryProvider.forTesting(
      repository: _StoredMemberRepo(),
      isHost: false,
    );
    await provider.reloadAllForTesting();
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryProvider>.value(
        value: provider,
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MembersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // New-member dialog first: enrichment pickers exist, photo affordance
    // does NOT (a brand-new row has no stable file key yet).
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('اختيار صورة'), findsNothing);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    // Edit path: open the stored member's editor via its pencil action.
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('اختيار صورة'), findsOneWidget);
    // Stored canonical 'Student'/'Active' display localized (RTL):
    expect(find.text('طالب'), findsOneWidget);
    expect(find.text('نشطة'), findsOneWidget);
  });
}

/// Repo stub carrying one v24-enriched member so the EDIT dialog opens with
/// real stored values (type/status/photo affordance/localized labels).
class _StoredMemberRepo implements LibraryRepository {
  @override
  Future<List<Member>> getMembers() async => [
    Member(
      id: 1,
      firstName: 'أمينة',
      lastName: 'بلقاسم',
      memberId: 'AA0100',
      registeredAt: DateTime(2024),
      memberType: 'Student',
      status: 'Active',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
