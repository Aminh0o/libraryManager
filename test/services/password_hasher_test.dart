import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/password_hasher.dart';

/// Tests encode the *intended* production behaviour of the credential hasher,
/// not the current app's old unsalted-SHA-256 behaviour (SEC-02).
void main() {
  // Fast iteration count for correctness tests; the default (150k) is asserted
  // separately so CI stays quick while production keeps the expensive setting.
  final hasher = PasswordHasher(iterations: 2000);

  group('PBKDF2-HMAC-SHA256 correctness', () {
    test('matches the PBKDF2 definition for c=1 (single block)', () {
      // For iterations=1 and a 32-byte key, DK == HMAC-SHA256(password, salt||INT(1)).
      final saltB64 = base64.encode(utf8.encode('fixed-salt-16bytes'));
      final stored = PasswordHasher(
        iterations: 1,
      ).hash('password', salt: saltB64);
      final derivedB64 = stored.split('|').last;

      final saltBytes = utf8.encode('fixed-salt-16bytes');
      final block = Uint8List(saltBytes.length + 4)
        ..setRange(0, saltBytes.length, saltBytes)
        ..[saltBytes.length] = 0
        ..[saltBytes.length + 1] = 0
        ..[saltBytes.length + 2] = 0
        ..[saltBytes.length + 3] = 1;
      final expected = Hmac(
        sha256,
        utf8.encode('password'),
      ).convert(block).bytes;

      expect(base64.decode(derivedB64), equals(expected));
    });

    test('salt is embedded and iterations are recorded in the format', () {
      final stored = hasher.hash('correct horse');
      final parts = stored.split('|');
      expect(parts.length, 5);
      expect(parts[0], 'pbkdf2');
      expect(parts[1], 'sha256');
      expect(parts[2], '2000');
      expect(base64.decode(parts[3]).length, 16); // salt
      expect(base64.decode(parts[4]).length, 32); // derived key
    });
  });

  group('verify()', () {
    test('accepts the right password', () {
      final stored = hasher.hash('s3cret!');
      expect(hasher.verify('s3cret!', stored), isTrue);
    });

    test('rejects a wrong password', () {
      final stored = hasher.hash('s3cret!');
      expect(hasher.verify('S3cret!', stored), isFalse);
      expect(hasher.verify('', stored), isFalse);
    });

    test('same password hashes differently each time (random salt)', () {
      final a = hasher.hash('repeat');
      final b = hasher.hash('repeat');
      expect(a, isNot(equals(b)));
      expect(hasher.verify('repeat', a), isTrue);
      expect(hasher.verify('repeat', b), isTrue);
    });

    test('is deterministic for a fixed salt + iterations', () {
      final salt = hasher.generateSalt();
      final a = PasswordHasher(iterations: 500).hash('det', salt: salt);
      final b = PasswordHasher(iterations: 500).hash('det', salt: salt);
      expect(a, equals(b));
    });

    test('rejects a tampered stored hash without throwing', () {
      final stored = hasher.hash('target');
      final parts = stored.split('|');
      final key = base64.decode(parts[4]);
      key[0] ^= 0x01;
      parts[4] = base64.encode(key);
      expect(hasher.verify('target', parts.join('|')), isFalse);
    });

    test(
      'never trusts the caller-provided iteration count to crash on garbage',
      () {
        expect(hasher.verify('x', 'not-a-valid-format'), isFalse);
        expect(hasher.verify('x', 'pbkdf2|sha256|abc|AA==|AA=='), isFalse);
        expect(hasher.verify('x', 'pbkdf2|sha512|10|AA==|AA=='), isFalse);
        expect(hasher.verify('x', 'pbkdf2|sha256|0|AA==|AA=='), isFalse);
      },
    );
  });

  group('tokens', () {
    test('generateToken is url-safe, unpadded and unpredictable', () {
      final h = PasswordHasher();
      final t = h.generateToken();
      expect(t.length, greaterThanOrEqualTo(43)); // >=256 bits, base64url
      expect(t.contains('='), isFalse);
      expect(t.contains('+'), isFalse);
      expect(t.contains('/'), isFalse);
      expect(h.generateToken(), isNot(equals(t)));
    });
  });

  test('production default iteration count is deliberately expensive', () {
    expect(PasswordHasher().iterations, greaterThanOrEqualTo(100000));
    expect(PasswordHasher.defaultIterations, greaterThanOrEqualTo(100000));
  });
}
