import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/api_service.dart';

/// Returns a canned status/body for every request and counts sends, so the test
/// can assert the message the client surfaces AND that a structured (non-2xx)
/// response is NOT blindly retried (only transport failures are) — BE-02.
class _CannedClient extends http.BaseClient {
  _CannedClient(this.status, this.body);

  final int status;
  final String body;
  int sends = 0;
  String? lastMethod;
  String? lastPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    lastMethod = request.method;
    lastPath = request.url.path;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

LibraryItem _item() => LibraryItem(
      code: '0700',
      codeType: 'LIV',
      designation: 'A book',
      quantite: 1,
      emplacement: 'A1',
      taux: 0,
      emplacementStock: 'S1',
    );

ApiService _api(http.Client client) =>
    ApiService(hostIp: '127.0.0.1', port: 9, client: client);

void main() {
  group('ApiService surfaces the server error (BE-02 / Phase 8.2)', () {
    test('a 409 delete-conflict becomes an ApiException with the real message',
        () async {
      final client = _CannedClient(
        409,
        jsonEncode({
          'error': 'conflict',
          'message': 'Membre a des prêts actifs',
        }),
      );
      Object? err;
      try {
        await _api(client).deleteMember('M1');
      } catch (e) {
        err = e;
      }
      expect(err, isA<ApiException>());
      final ae = err! as ApiException;
      expect(ae.statusCode, 409);
      expect(ae.isConflict, isTrue);
      expect(ae.message, 'Membre a des prêts actifs');
      expect(ae.error, 'conflict');
      expect(client.lastMethod, 'DELETE');
      expect(client.lastPath, '/members/M1');
    });

    test('a 500 carries the server message instead of a generic string',
        () async {
      final client = _CannedClient(
        500,
        jsonEncode({'error': 'internal_error', 'message': 'boom'}),
      );
      await expectLater(
        _api(client).addItem(_item()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', 'boom'),
        ),
      );
    });

    test('a non-JSON error body falls back to the raw text', () async {
      final client = _CannedClient(502, 'Bad Gateway from proxy');
      await expectLater(
        _api(client).getStats(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.message, 'message', contains('Bad Gateway')),
        ),
      );
    });

    test('a structured error response is NOT retried (only transport errors)',
        () async {
      final client = _CannedClient(
        400,
        jsonEncode({'error': 'bad_request', 'message': 'nope'}),
      );
      await expectLater(
        _api(client).updateItem(_item()),
        throwsA(isA<ApiException>()),
      );
      // _retry only re-sends on Client/Socket/Timeout exceptions; an ApiException
      // (a definitive HTTP error) must reach the caller after a single attempt.
      expect(client.sends, 1);
    });
  });
}
