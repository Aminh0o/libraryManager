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
