import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/l10n/app_localizations.dart';
import 'package:library_manager/services/api_service.dart' show ApiException;
import 'package:library_manager/services/database_service.dart'
    show
        ActiveLoanConflictException,
        AttributeConflictException,
        BarcodeConflictException,
        ConcurrentUpdateConflictException,
        ItemCodeConflictException,
        MemberIdConflictException;
import 'package:library_manager/services/error_messages.dart';

/// FE2-12: every `catch` used to show the raw `'Erreur: $e'` — leaking
/// exception class names and internal server text to the operator, in French
/// only, with no categorisation. [describeError] maps an error to a SHORT,
/// LOCALIZED category instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('ApiException is categorised by its HTTP status', () {
    expect(describeError(l10n, ApiException(401, 'x')), l10n.errAuth);
    expect(describeError(l10n, ApiException(403, 'x')), l10n.errAuth);
    expect(describeError(l10n, ApiException(404, 'x')), l10n.errNotFound);
    expect(describeError(l10n, ApiException(409, 'x')), l10n.errConflict);
    expect(describeError(l10n, ApiException(400, 'x')), l10n.errBadRequest);
    expect(describeError(l10n, ApiException(500, 'x')), l10n.errServerError);
    expect(describeError(l10n, ApiException(503, 'x')), l10n.errServerError);
    // An unmapped 4xx falls through to the generic bucket, never the raw body.
    expect(describeError(l10n, ApiException(418, 'x')), l10n.errGeneric);
  });

  test('transport failures map to the network message', () {
    expect(describeError(l10n, http.ClientException('connection refused')),
        l10n.errNetwork);
    expect(describeError(l10n, TimeoutException('operation timed out')),
        l10n.errNetwork);
  });

  test('host-side typed integrity conflicts all map to the conflict message',
      () {
    for (final e in <Object>[
      ItemCodeConflictException('dup code'),
      BarcodeConflictException('dup barcode'),
      MemberIdConflictException('dup member id'),
      AttributeConflictException('dup attribute'),
      ActiveLoanConflictException('still on loan'),
      ConcurrentUpdateConflictException('row changed'),
    ]) {
      expect(describeError(l10n, e), l10n.errConflict, reason: '$e');
    }
  });

  test('an unknown error never leaks its raw text to the operator', () {
    final result =
        describeError(l10n, Exception('SQLITE_CONSTRAINT near line 42'));
    expect(result, l10n.errGeneric);
    expect(result.contains('SQLITE'), isFalse);
    expect(result.contains('line 42'), isFalse);
  });

  test('the categorized strings are localized per locale', () async {
    final fr = await AppLocalizations.delegate.load(const Locale('fr'));
    // The SAME category resolves to a different locale's wording, proving the
    // message comes from the ARBs and not a hardcoded French 'Erreur: $e'.
    expect(describeError(fr, ApiException(409, 'x')), isNot(l10n.errConflict));
    expect(describeError(fr, ApiException(409, 'x')), fr.errConflict);
  });
}
