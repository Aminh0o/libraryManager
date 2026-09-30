import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// Records what filters the HTTP routes forward to the [LibraryRepository] seam
/// and returns canned results — proving the query-string → repository wiring
/// (FE-05 / Phase 7) without a database. This file deliberately avoids
/// `TestWidgetsFlutterBinding`, whose interceptor would force every `HttpClient`
/// call to a 400 (see the repo's other socket tests).
class _RecordingRepo implements LibraryRepository {
  final List<Map<String, Object?>> getItemsCalls = [];
  final List<Map<String, Object?>> countItemsCalls = [];
  List<LibraryItem> itemsToReturn = const [];
  int countToReturn = 0;

  @override
  dynamic noSuchMethod(Invocation inv) {
    if (inv.memberName == #getItems) {
      getItemsCalls.add({
        'search': inv.namedArguments[#search],
        'status': inv.namedArguments[#status],
        'codeType': inv.namedArguments[#codeType],
        'limit': inv.namedArguments[#limit],
        'offset': inv.namedArguments[#offset],
      });
      return Future.value(itemsToReturn);
    }
    if (inv.memberName == #countItems) {
      countItemsCalls.add({
        'search': inv.namedArguments[#search],
        'status': inv.namedArguments[#status],
        'codeType': inv.namedArguments[#codeType],
      });
      return Future.value(countToReturn);
    }
    return super.noSuchMethod(inv);
  }
}

LibraryItem _item(String code) => LibraryItem(
      code: code,
      codeType: 'LIV',
      designation: 'Title $code',
      quantite: 1,
      emplacement: 'A',
      taux: 0,
      emplacementStock: 'S',
    );

void main() {
  late HttpServerService server;
  late _RecordingRepo repo;
  late http.Client client;
  late String base;

  setUp(() async {
    repo = _RecordingRepo();
    server = HttpServerService(repository: repo);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  test('GET /items forwards search/status/codeType/limit/offset to the repo',
      () async {
    repo.itemsToReturn = [_item('0007')];
    final res = await client.get(Uri.parse(
        '$base/items?search=Titre%200007&status=Emprunt%C3%A9&codeType=LIV&limit=20&offset=40'));
    expect(res.statusCode, 200);
    expect(repo.getItemsCalls, hasLength(1));
    final a = repo.getItemsCalls.single;
    expect(a['search'], 'Titre 0007');
    expect(a['status'], 'Emprunté');
    expect(a['codeType'], 'LIV');
    expect(a['limit'], 20);
    expect(a['offset'], 40);
    // The handler serialises the repository's page.
    final body = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    expect(body.map((m) => m['code']).toList(), ['0007']);
  });

  test('omitted query params are forwarded as null (no constraint)', () async {
    await client.get(Uri.parse('$base/items'));
    final a = repo.getItemsCalls.single;
    expect(a['search'], isNull);
    expect(a['status'], isNull);
    expect(a['codeType'], isNull);
    expect(a['limit'], 1000); // route default
    expect(a['offset'], 0);
  });

  test('GET /items/count forwards filters and returns {count}', () async {
    repo.countToReturn = 10;
    final res =
        await client.get(Uri.parse('$base/items/count?codeType=REV'));
    expect(res.statusCode, 200);
    expect(jsonDecode(res.body), {'count': 10});
    expect(repo.countItemsCalls.single['codeType'], 'REV');
  });
}
