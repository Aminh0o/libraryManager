import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Server-side password hashing and secure token primitives.
///
/// This replaces the previous security model that stored a single unsalted
/// SHA-256 hash of the admin password (SEC-02). Passwords are now stretched
/// with **PBKDF2-HMAC-SHA256** using a per-credential random salt and a high
/// iteration count, which is deliberately expensive and resists offline
/// brute-forcing. Raw passwords are never stored or logged.
///
/// The stored format is:
///
///     pbkdf2|sha256|<iterations>|<base64 salt>|<base64 derived key>
///
/// Implemented in pure Dart on top of `package:crypto` so it works identically
/// on the Windows host with no native dependency.
class PasswordHasher {
  /// PBKDF2 iteration count used for real credentials. Deliberately high; the
  /// cost is paid only when a password is set or verified (rare operations).
  static const int defaultIterations = 150000;

  static const int _saltBytes = 16;
  static const int _derivedKeyBytes = 32;
  static const int _hmacOutBytes = 32; // SHA-256 output length.

  final int iterations;
  final Random _rng;

  PasswordHasher({this.iterations = defaultIterations, Random? rng})
      : _rng = rng ?? Random.secure();

  /// Returns a fresh random salt, base64-encoded.
  String generateSalt() => base64.encode(_randomBytes(_saltBytes));

  /// Returns a URL-safe random token (no padding). Used for LAN auth tokens.
  String generateToken([int bytes = 32]) =>
      base64Url.encode(_randomBytes(bytes)).replaceAll('=', '');

  /// Derives a PBKDF2-HMAC-SHA256 hash for [password]. When [salt] is omitted a
  /// new random salt is generated, so identical passwords yield distinct hashes.
  String hash(String password, {String? salt}) {
    final saltB64 = salt ?? generateSalt();
    final saltBytes = base64.decode(saltB64);
    final derived = _pbkdf2(utf8.encode(password), saltBytes, iterations,
        _derivedKeyBytes);
    return [
      'pbkdf2',
      'sha256',
      '$iterations',
      saltB64,
      base64.encode(derived),
    ].join('|');
  }

  /// Verifies [password] against a [stored] hash string. Safe against malformed
  /// stored values (returns false rather than throwing) and uses constant-time
  /// comparison to avoid leaking derived-key content.
  bool verify(String password, String stored) {
    final parts = stored.split('|');
    if (parts.length != 5 || parts[0] != 'pbkdf2' || parts[1] != 'sha256') {
      return false;
    }
    final iters = int.tryParse(parts[2]);
    if (iters == null || iters <= 0) return false;
    late final Uint8List salt;
    late final Uint8List expected;
    try {
      salt = base64.decode(parts[3]);
      expected = base64.decode(parts[4]);
    } on FormatException {
      return false;
    }
    if (expected.isEmpty) return false;
    final derived = _pbkdf2(utf8.encode(password), salt, iters, expected.length);
    return _constantTimeEquals(derived, expected);
  }

  Uint8List _randomBytes(int length) {
    final b = Uint8List(length);
    for (var i = 0; i < length; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations,
      int dkLen) {
    final prf = Hmac(sha256, password);
    final blockCount = (dkLen + _hmacOutBytes - 1) ~/ _hmacOutBytes;
    final output = Uint8List(blockCount * _hmacOutBytes);
    final block = Uint8List(salt.length + 4)..setRange(0, salt.length, salt);

    for (var i = 1; i <= blockCount; i++) {
      block[salt.length] = (i >> 24) & 0xff;
      block[salt.length + 1] = (i >> 16) & 0xff;
      block[salt.length + 2] = (i >> 8) & 0xff;
      block[salt.length + 3] = i & 0xff;

      var u = Uint8List.fromList(prf.convert(block).bytes);
      final t = Uint8List.fromList(u);
      for (var c = 1; c < iterations; c++) {
        u = Uint8List.fromList(prf.convert(u).bytes);
        for (var j = 0; j < _hmacOutBytes; j++) {
          t[j] ^= u[j];
        }
      }
      output.setRange((i - 1) * _hmacOutBytes, i * _hmacOutBytes, t);
    }
    return Uint8List.sublistView(output, 0, dkLen);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
