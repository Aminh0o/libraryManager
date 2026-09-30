import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/ui/app_tokens.dart';
import 'package:library_manager/widgets/app_status_chip.dart';
import 'package:library_manager/widgets/item_status_cell.dart';

/// Phase 12: a title's status is ALWAYS the copy-derived rollup (BL-05), so the
/// inventory grid cell is a READ-ONLY chip for host and client alike — the
/// inline title-status editor was removed (any such write is now overridden by,
/// or validated against, the copy ledger, so leaving it would only mislead).
/// Together these cases pin (a) that no editable control is ever handed out —
/// the old FE2-04 permission inversion can no longer be expressed at all — and
/// (b) that the full copy-derived vocabulary renders truthfully (FE2-06).
Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the HOST gets a read-only derived chip, NOT an editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ItemStatusCell(status: ItemStatus.disponible, isHost: true)),
    );

    expect(
      find.byType(DropdownButton<String>),
      findsNothing,
      reason:
          'status is derived from copies; the grid must not hand out an '
          'inline title-status editor',
    );
    expect(find.byType(PopupMenuButton<Object>), findsNothing);
    expect(
      find.text('Disponible'),
      findsOneWidget,
      reason: 'the derived status is still displayed, just not editable',
    );
  });

  testWidgets('a CLIENT also gets a read-only chip', (tester) async {
    await tester.pumpWidget(
      _wrap(const ItemStatusCell(status: ItemStatus.emprunte, isHost: false)),
    );

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Emprunté'), findsOneWidget);
  });

  testWidgets('a copy-derived status outside the old ItemStatus set renders '
      'localized, NOT raw (En Réparation)', (tester) async {
    // 'En Réparation' is only ever produced by the copy rollup post-BL-05. The
    // chip must translate it (fr 'En réparation') rather than show the raw
    // storage string — a discriminator, since the two differ by case.
    await tester.pumpWidget(
      _wrap(const ItemStatusCell(status: 'En Réparation')),
    );
    expect(find.text('En réparation'), findsOneWidget);
    expect(find.text('En Réparation'), findsNothing);
  });

  testWidgets('an untranslatable legacy / DB-only status renders its raw value '
      'truthfully (FE2-06)', (tester) async {
    await tester.pumpWidget(_wrap(const ItemStatusCell(status: 'Payé')));
    expect(
      find.text('Payé'),
      findsOneWidget,
      reason:
          'a value the app cannot translate must be shown as-is, never '
          'coerced to a friendly default',
    );
  });

  test('statusColor tints the vocabulary from the ONE centralized palette', () {
    // Phase C (frontend reconstruction): the old per-chip Material swatches
    // (disponible was blue, emprunté purple, …) are retired in favour of the
    // centralized AppStatus semantics, so a status reads identically on every
    // surface: disponible=green, emprunté=blue, réservé=orange, endommagé=red,
    // réparation=magenta, perdu=brown, archivé=blue-grey, unknown=neutral grey.
    expect(
      ItemStatusCell.statusColor(ItemStatus.disponible),
      AppStatus.available,
    );
    expect(ItemStatusCell.statusColor(ItemStatus.emprunte), AppStatus.borrowed);
    expect(ItemStatusCell.statusColor(ItemStatus.reserve), AppStatus.reserved);
    expect(ItemStatusCell.statusColor(ItemStatus.endommage), AppStatus.damaged);
    expect(ItemStatusCell.statusColor('En Réparation'), AppStatus.repair);
    expect(ItemStatusCell.statusColor('Perdu'), AppStatus.lost);
    expect(ItemStatusCell.statusColor('Archivé'), AppStatus.archived);
    expect(
      ItemStatusCell.statusColor('Payé'),
      AppStatus.neutral,
      reason: 'an unknown value falls back to the neutral chip',
    );
  });

  testWidgets('the cell renders through the shared AppStatusChip (§44)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const ItemStatusCell(status: ItemStatus.disponible)),
    );
    expect(
      find.byType(AppStatusChip),
      findsOneWidget,
      reason: 'status tinting lives in exactly one chip implementation',
    );
  });
}
