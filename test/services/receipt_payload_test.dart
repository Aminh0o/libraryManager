import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/receipt_payload.dart';

/// §6.12 QR/barcode semantics: a printed code is a RECORD IDENTIFIER, never an
/// action and never PII. These tests pin the exact guarantees the prompt calls
/// out — opaque-id-only payloads, strict rejection of malformed / unknown-
/// version / wrong-subsystem codes, and total separation from the LAN-pairing QR.
void main() {
  group('encodeReceiptPayload', () {
    test('round-trips every document type through an opaque id', () {
      for (final type in ReceiptDocType.values) {
        final payload = encodeReceiptPayload(type: type, ref: 'A-1_b-99');
        final decoded = decodeReceiptPayload(payload);
        expect(decoded, isNotNull, reason: 'type ${type.code} must decode');
        expect(decoded!.type, type);
        expect(decoded.ref, 'A-1_b-99');
        expect(decoded.version, kReceiptPayloadVersion);
        expect(payload, 'LM1|${type.code}|A-1_b-99');
      }
    });

    test('refuses an empty reference', () {
      expect(
        () => encodeReceiptPayload(type: ReceiptDocType.loan, ref: ''),
        throwsA(isA<ReceiptPayloadException>()),
      );
    });

    test('refuses a reference carrying PII or separator characters', () {
      const unsafe = <String>[
        'Jean Dupont', // name, has a space
        'a@b.com', // email
        '+33 6 12 34 56', // phone
        'x|y', // field separator smuggling
        'x:y', // collides with the pairing format
        '1.2.3.4', // dotted / non-opaque
        'café', // non-ASCII
        '', // handled separately but keep pattern coverage
      ];
      for (final ref in unsafe) {
        if (ref.isEmpty) continue;
        expect(
          () => encodeReceiptPayload(type: ReceiptDocType.card, ref: ref),
          throwsA(isA<ReceiptPayloadException>()),
          reason: 'a payload must never embed: $ref',
        );
      }
    });

    test('refuses an over-long reference', () {
      final tooLong = 'a' * 65;
      expect(
        () => encodeReceiptPayload(type: ReceiptDocType.hold, ref: tooLong),
        throwsA(isA<ReceiptPayloadException>()),
      );
    });
  });

  group('decodeReceiptPayload (strict, never mutates, never guesses)', () {
    test('accepts a well-formed current-version code', () {
      final p = decodeReceiptPayload('LM1|LOAN|42');
      expect(p, isNotNull);
      expect(p!.type, ReceiptDocType.loan);
      expect(p.ref, '42');
    });

    test('rejects the LAN-pairing code as a receipt (separate subsystem)', () {
      expect(decodeReceiptPayload('LIB_SYNC:192.168.1.5'), isNull);
      expect(isPairingPayload('LIB_SYNC:192.168.1.5'), isTrue);
      expect(isPairingPayload('LM1|CARD|42'), isFalse);
    });

    test('rejects unknown / future scheme versions', () {
      expect(decodeReceiptPayload('LM2|LOAN|42'), isNull);
      expect(decodeReceiptPayload('LM99|CARD|42'), isNull);
      expect(decodeReceiptPayload('SOMETHING|CARD|42'), isNull);
    });

    test('rejects unknown document-type codes', () {
      expect(decodeReceiptPayload('LM1|WIFI|42'), isNull);
    });

    test('rejects malformed field counts', () {
      expect(decodeReceiptPayload('LM1|LOAN'), isNull);
      expect(decodeReceiptPayload('LM1|LOAN|42|extra'), isNull);
      expect(decodeReceiptPayload('LM1||'), isNull);
    });

    test('rejects references with illegal characters or control bytes', () {
      expect(decodeReceiptPayload('LM1|LOAN|a b'), isNull);
      expect(decodeReceiptPayload('LM1|LOAN|jean@x'), isNull);
      // Embedded newline / NUL would smuggle data; a lone pipe already breaks
      // the field count, but a control char on its own must also be refused.
      expect(decodeReceiptPayload('LM1|LOAN|4\n2'), isNull);
      expect(decodeReceiptPayload(''), isNull);
    });
  });

  test('a printed payload never contains a name, contact or secret field', () {
    // The alphabet guard is the mechanism; prove the wire form is inert text.
    final payload = encodeReceiptPayload(
      type: ReceiptDocType.card,
      ref: 'M2026',
    );
    expect(payload.contains('@'), isFalse);
    expect(payload.contains(' '), isFalse);
    expect(payload.split('|').length, 3);
  });
}
