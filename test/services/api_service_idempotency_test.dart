import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/services/api_service.dart';

/// A fake client that records the headers of every attempt and can simulate a
/// connection drop (a retryable [SocketException]) on the first N sends — the
/// exact situation that, without an idempotency key, makes `_retry` create a
/// duplicate row (REL-03 / TX-05).
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.dropFirst = 0});

  final int dropFirst;
  final List<Map<String, String>> sentHeaders = [];
  final List<String> sentPaths = [];
  int _calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _calls++;
    // http stores header keys lower-cased; copy defensively regardless.
    sentHeaders.add(Map<String, String>.from(request.headers));
    sentPaths.add(request.url.path);
    if (_calls <= dropFirst) {
      throw const SocketException('simulated mid-request drop');
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(const <List<int>>[]),
      200,
    );
  }
}

String? idemKey(Map<String, String> headers) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == 'idempotency-key') return e.value;
  }
  return null;
}

LibraryItem sampleItem() => LibraryItem(
  code: '0700',
  codeType: 'LIV',
  designation: 'A book',
  quantite: 1,
  emplacement: 'A1',
  taux: 0,
  emplacementStock: 'S1',
);

void main() {
  group('ApiService emits a stable Idempotency-Key (REL-03 / 6.2)', () {
    test(
      'a retried POST after a mid-request drop reuses the SAME key',
      () async {
        final client = _RecordingClient(dropFirst: 1);
        final api = ApiService(
          hostIp: '127.0.0.1',
          port: 9,
          client: client,
        ); // timeout default 3s

        await api.addItem(sampleItem()); // _retry: 1 drop + 1 success

        expect(client.sentPaths, ['/items', '/items']); // two attempts
        final k1 = idemKey(client.sentHeaders[0]);
        final k2 = idemKey(client.sentHeaders[1]);
        expect(k1, isNotNull);
        expect(k1, isNotEmpty);
        expect(
          k1,
          k2,
          reason: 'the retry must carry the original operation key',
        );
      },
    );

    test('two separate addItem calls get DIFFERENT keys', () async {
      final client = _RecordingClient();
      final api = ApiService(
        hostIp: '127.0.0.1',
        port: 9,
        client: client,
        timeout: const Duration(seconds: 1),
      );

      await api.addItem(sampleItem());
      await api.addItem(sampleItem());

      final k1 = idemKey(client.sentHeaders[0]);
      final k2 = idemKey(client.sentHeaders[1]);
      expect(k1, isNotNull);
      expect(k2, isNotNull);
      expect(k1, isNot(k2));
    });

    test('every non-idempotent POST mutation carries a key', () async {
      final client = _RecordingClient();
      final api = ApiService(
        hostIp: '127.0.0.1',
        port: 9,
        client: client,
        timeout: const Duration(seconds: 1),
      );

      await api.addItem(sampleItem());
      await api.addMember(
        Member(
          memberId: 'M1',
          firstName: 'Ann',
          lastName: 'Lee',
          registeredAt: DateTime(2026),
        ),
      );
      await api.addLoan(
        Loan(
          id: 1,
          itemCode: '0700',
          memberId: 'M1',
          memberName: 'Ann Lee',
          itemTitle: 'A book',
          loanDate: DateTime(2026),
          dueDate: DateTime(2026, 2, 1),
        ),
      );
      await api.addHistoryEntry({'operation': 'X', 'details': 'd'});
      await api.addCodeDefinition('LIV', 'Livres');
      await api.addAttributeDefinition('status', 'Disponible');

      // Every send in this group is a POST mutation and must be keyed.
      for (var i = 0; i < client.sentHeaders.length; i++) {
        final k = idemKey(client.sentHeaders[i]);
        expect(
          k,
          isNotNull,
          reason: 'send #$i (${client.sentPaths[i]}) must be keyed',
        );
        expect(k, isNotEmpty);
      }
      expect(
        client.sentPaths,
        containsAll(<String>[
          '/items',
          '/members',
          '/loans',
          '/history',
          '/code-definitions',
          '/attribute-definitions',
        ]),
      );
    });

    test('idempotency keys are unique across many operations', () async {
      final client = _RecordingClient();
      final api = ApiService(
        hostIp: '127.0.0.1',
        port: 9,
        client: client,
        timeout: const Duration(seconds: 1),
      );
      final keys = <String>{};
      for (var i = 0; i < 50; i++) {
        await api.addItem(sampleItem());
        keys.add(idemKey(client.sentHeaders.last)!);
      }
      expect(keys.length, 50);
      // Sanity: keys are opaque hex strings.
      for (final k in keys) {
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(k), isTrue);
        expect(jsonDecode('{"k":"$k"}')['k'], k); // must be header/JSON safe
      }
    });
  });
}
