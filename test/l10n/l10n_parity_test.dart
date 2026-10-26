import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/l10n/app_localizations.dart';

void main() {
  late Map<String, dynamic> enJson;
  late Map<String, dynamic> frJson;
  late Map<String, dynamic> arJson;

  late Set<String> enKeys;
  late Set<String> frKeys;
  late Set<String> arKeys;

  setUpAll(() {
    final enFile = File('lib/l10n/app_en.arb');
    final frFile = File('lib/l10n/app_fr.arb');
    final arFile = File('lib/l10n/app_ar.arb');

    expect(enFile.existsSync(), isTrue, reason: 'app_en.arb must exist');
    expect(frFile.existsSync(), isTrue, reason: 'app_fr.arb must exist');
    expect(arFile.existsSync(), isTrue, reason: 'app_ar.arb must exist');

    enJson = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
    frJson = jsonDecode(frFile.readAsStringSync()) as Map<String, dynamic>;
    arJson = jsonDecode(arFile.readAsStringSync()) as Map<String, dynamic>;

    enKeys = enJson.keys.where((k) => !k.startsWith('@')).toSet();
    frKeys = frJson.keys.where((k) => !k.startsWith('@')).toSet();
    arKeys = arJson.keys.where((k) => !k.startsWith('@')).toSet();
  });

  group('ARB key parity across all locales', () {
    test(
      'all three catalogues have the same total number of translation keys',
      () {
        expect(enKeys.length, greaterThan(400));
        expect(
          frKeys.length,
          equals(enKeys.length),
          reason: 'French must have exact same key count as English',
        );
        expect(
          arKeys.length,
          equals(enKeys.length),
          reason: 'Arabic must have exact same key count as English',
        );
      },
    );

    test(
      'app_fr.arb has key parity with app_en.arb (no missing or orphan keys)',
      () {
        final missingInFr = enKeys.difference(frKeys);
        final orphanInFr = frKeys.difference(enKeys);
        expect(
          missingInFr,
          isEmpty,
          reason: 'French is missing keys defined in English: $missingInFr',
        );
        expect(
          orphanInFr,
          isEmpty,
          reason: 'French has orphan keys not in English: $orphanInFr',
        );
      },
    );

    test(
      'app_ar.arb has key parity with app_en.arb (no missing or orphan keys)',
      () {
        final missingInAr = enKeys.difference(arKeys);
        final orphanInAr = arKeys.difference(enKeys);
        expect(
          missingInAr,
          isEmpty,
          reason: 'Arabic is missing keys defined in English: $missingInAr',
        );
        expect(
          orphanInAr,
          isEmpty,
          reason: 'Arabic has orphan keys not in English: $orphanInAr',
        );
      },
    );
  });

  group('Placeholder parity across all locales', () {
    Set<String> extractPlaceholders(String text) {
      final exp = RegExp(r'\{([a-zA-Z0-9_]+)\}');
      return exp.allMatches(text).map((m) => m.group(1)!).toSet();
    }

    test('all placeholders in English match French and Arabic exactly', () {
      for (final key in enKeys) {
        final enVal = enJson[key]?.toString() ?? '';
        final frVal = frJson[key]?.toString() ?? '';
        final arVal = arJson[key]?.toString() ?? '';

        expect(enVal.trim(), isNotEmpty, reason: 'Key $key in EN is empty');
        expect(frVal.trim(), isNotEmpty, reason: 'Key $key in FR is empty');
        expect(arVal.trim(), isNotEmpty, reason: 'Key $key in AR is empty');

        final enPlaceholders = extractPlaceholders(enVal);
        final frPlaceholders = extractPlaceholders(frVal);
        final arPlaceholders = extractPlaceholders(arVal);

        expect(
          frPlaceholders,
          equals(enPlaceholders),
          reason:
              'Placeholder mismatch for key "$key": EN=$enPlaceholders, FR=$frPlaceholders',
        );
        expect(
          arPlaceholders,
          equals(enPlaceholders),
          reason:
              'Placeholder mismatch for key "$key": EN=$enPlaceholders, AR=$arPlaceholders',
        );
      }
    });
  });

  group('Translation authenticity (a key existing is not being translated)', () {
    // A real-UI pass caught `totalDocuments` shipping as the English literal
    // "Total Documents" inside the FRENCH catalogue. Key-set parity is blind to
    // that whole defect class: the key exists, the placeholder matches, the
    // value is non-empty -- and the user still sees English. These checks
    // compare VALUES, which is the only thing the UI can reveal.
    //
    // Allowlist: words that are legitimately identical in French (cognates the
    // Académie française accepts as-is) and machine-format strings. Adding a key
    // here must be a deliberate, reviewed choice -- each entry is an admission
    // that a French reader is being shown the English text.
    const frIdenticalOk = {
      'code', // FR: code
      'stock', // FR: stock
      'typeLabel', // FR: type
      'actions', // FR: actions
      'clientMode', // FR: client
      'memberIdCode', // FR: ID / Code
      'email', // FR: Email (also accepted: e-mail)
      'typeStandard', // FR: standard
      'notes', // FR: notes
      'photo', // FR: photo
      'itemDescription', // FR: description
      'flash', // FR: flash
      'stepConfiguration', // FR: configuration
      'fineDateLabel', // FR: date
      'reportKindCirculation', // FR: circulation
      'notifications', // FR: notifications
      'chatInputHint', // FR: message
    };

    bool isMachineText(String v) =>
        v.isEmpty ||
        v.contains('http') ||
        v.contains('@') ||
        v.contains('{') || // placeholder-only
        RegExp(r'^[^\p{L}]+$', unicode: true).hasMatch(v); // punctuation/digits

    test('no French value is an untranslated English literal', () {
      final offenders = <String>[];
      for (final key in enKeys) {
        if (frIdenticalOk.contains(key)) continue;
        final enVal = enJson[key]?.toString() ?? '';
        final frVal = frJson[key]?.toString() ?? '';
        if (isMachineText(enVal)) continue;
        if (enVal.trim().toLowerCase() == frVal.trim().toLowerCase()) {
          offenders.add('$key: "$enVal"');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'These French entries are still English text and will render as '
            'English for a French reader:\n${offenders.join('\n')}',
      );
    });

    test('every Arabic value that carries words contains Arabic script', () {
      final arabic = RegExp(r'[\u0600-\u06FF]');
      final offenders = <String>[];
      for (final key in enKeys) {
        final enVal = enJson[key]?.toString() ?? '';
        final arVal = arJson[key]?.toString() ?? '';
        if (isMachineText(enVal)) continue;
        if (!arabic.hasMatch(arVal)) {
          offenders.add('$key: "$arVal"');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'These Arabic entries contain no Arabic script and will render as '
            'Latin text for an Arabic reader:\n${offenders.join('\n')}',
      );
    });

    test('a stated count in a tutorial string matches the shipped content', () {
      // The help-center subtitle announces how many guided paths exist. The
      // real count lives in HelpCenterScreen's group list, so the two drift: a
      // copy said "Eighteen" while the screen rendered nineteen.
      final subtitle = enJson['tutorialMapSubtitle']?.toString() ?? '';
      final stated = RegExp(
        r'\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
        r'thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)\b',
        caseSensitive: false,
      ).firstMatch(subtitle);
      expect(stated, isNotNull, reason: 'subtitle must state a path count');

      final words = {
        'one': 1,
        'two': 2,
        'three': 3,
        'four': 4,
        'five': 5,
        'six': 6,
        'seven': 7,
        'eight': 8,
        'nine': 9,
        'ten': 10,
        'eleven': 11,
        'twelve': 12,
        'thirteen': 13,
        'fourteen': 14,
        'fifteen': 15,
        'sixteen': 16,
        'seventeen': 17,
        'eighteen': 18,
        'nineteen': 19,
        'twenty': 20,
      };
      final parsed = int.tryParse(stated!.group(1)!);
      final count = parsed ?? words[stated.group(1)!.toLowerCase()];
      expect(count, isNotNull);

      // Count the tstepN pairs actually defined in the catalogue.
      final steps = <String>{};
      for (final key in enKeys) {
        final m = RegExp(r'^tstep(\d+)Title$').firstMatch(key);
        if (m != null) steps.add(m.group(1)!);
      }
      expect(
        count,
        equals(steps.length),
        reason:
            'tutorialMapSubtitle announces $count paths but the catalogue '
            'defines ${steps.length} (tstepNTitle keys). Update the copy in '
            'all three locales when the tutorial map changes.',
      );
    });
  });

  group('Arabic RTL and localizations runtime verification', () {
    testWidgets('AppLocalizations loads Arabic with RTL text direction', (
      tester,
    ) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return Scaffold(body: Text(AppLocalizations.of(ctx)!.appTitle));
            },
          ),
        ),
      );

      final direction = Directionality.of(capturedContext);
      expect(
        direction,
        equals(TextDirection.rtl),
        reason: 'Arabic locale must resolve to TextDirection.rtl',
      );

      final l10n = AppLocalizations.of(capturedContext)!;
      expect(l10n.appTitle, isNotEmpty);
      expect(find.text(l10n.appTitle), findsOneWidget);
    });

    testWidgets(
      'AppLocalizations loads French and English with LTR text direction',
      (tester) async {
        for (final locale in [const Locale('en'), const Locale('fr')]) {
          late BuildContext capturedContext;
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: locale,
              home: Builder(
                builder: (ctx) {
                  capturedContext = ctx;
                  return Scaffold(
                    body: Text(AppLocalizations.of(ctx)!.appTitle),
                  );
                },
              ),
            ),
          );

          final direction = Directionality.of(capturedContext);
          expect(
            direction,
            equals(TextDirection.ltr),
            reason:
                '${locale.languageCode} locale must resolve to TextDirection.ltr',
          );
        }
      },
    );
  });
}
