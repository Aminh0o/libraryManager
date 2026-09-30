import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/pairing_protocol.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);
  final future = now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;

  group('encodePairingResponse', () {
    test('carries the real advertised port', () {
      final s = encodePairingResponse(
          code: '123456', ip: '192.168.1.5', port: 9090, expiresEpochMs: future);
      expect(s, 'LIB_PAIR_RESP:123456:192.168.1.5:9090:$future');
    });
    test('omits the token field when empty', () {
      final s = encodePairingResponse(
          code: '1', ip: '10.0.0.2', port: 8080, expiresEpochMs: future);
      expect(s.split(':').length, 5);
    });
    test('appends a non-empty token', () {
      final s = encodePairingResponse(
          code: '1', ip: '10.0.0.2', port: 8080, expiresEpochMs: future, token: 'abc');
      expect(s, 'LIB_PAIR_RESP:1:10.0.0.2:8080:$future:abc');
    });
  });

  group('decodePairingResponse', () {
    test('round-trips encode -> decode preserving port + token', () {
      final wire = encodePairingResponse(
          code: '42', ip: '192.168.0.9', port: 45678, expiresEpochMs: future, token: 'tk');
      final r = decodePairingResponse(wire, expectedCode: '42', now: now);
      expect(r, isNotNull);
      expect(r!.ip, '192.168.0.9');
      expect(r.port, 45678);
      expect(r.token, 'tk');
    });

    test('accepts any valid port (no longer pinned to 8080)', () {
      for (final port in [1, 8080, 9090, 65535]) {
        final wire = encodePairingResponse(
            code: '7', ip: '1.2.3.4', port: port, expiresEpochMs: future);
        final r = decodePairingResponse(wire, expectedCode: '7', now: now);
        expect(r?.port, port, reason: 'port $port must be honored');
      }
    });

    test('token is null for a 5-field legacy response', () {
      final r = decodePairingResponse(
          'LIB_PAIR_RESP:7:1.2.3.4:8080:$future',
          expectedCode: '7',
          now: now);
      expect(r?.token, isNull);
      expect(r?.ip, '1.2.3.4');
    });

    test('rejects wrong code / expiry / malformed / bad port / empty ip', () {
      final good =
          'LIB_PAIR_RESP:7:1.2.3.4:8080:$future';
      PairingResponse? d(String s, {String code = '7', DateTime? at}) =>
          decodePairingResponse(s, expectedCode: code, now: at ?? now);

      expect(d(good, code: '8'), isNull, reason: 'code mismatch');
      expect(d(good, at: now.add(const Duration(minutes: 6))), isNull,
          reason: 'expired');
      expect(d('LIB_PAIR_RESP:7:1.2.3.4:8080'), isNull, reason: 'too few fields');
      expect(d('LIB_OTHER:7:1.2.3.4:8080:$future'), isNull, reason: 'wrong prefix');
      expect(d('LIB_PAIR_RESP:7:1.2.3.4:0:$future'), isNull, reason: 'port 0');
      expect(d('LIB_PAIR_RESP:7:1.2.3.4:70000:\$future'), isNull,
          reason: 'port > 65535');
      expect(d('LIB_PAIR_RESP:7:1.2.3.4:notaport:$future'), isNull,
          reason: 'non-integer port');
      expect(d('LIB_PAIR_RESP:7:1.2.3.4:8080:nan'), isNull,
          reason: 'non-integer expiry');
      expect(d('LIB_PAIR_RESP:7::8080:$future'), isNull, reason: 'empty ip');
    });
  });
}
