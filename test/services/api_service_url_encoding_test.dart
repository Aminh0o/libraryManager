import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/services/api_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/repository.dart';

/// FB-04 (path-segment half): dynamic ids interpolated raw into `Uri.parse`
/// could break out of their path segment -- an item code / scanned barcode /
/// definition prefix / member id containing `/`, `#`, `?`, a space or non-ASCII
/// (legacy or hand-entered) would hit the wrong route or 404. `ApiService` now
/// percent-encodes each dynamic segment; the shelf router on the host decodes it
/// back. This drives the REAL client against the REAL server on a loopback
/// socket, so it exercises the full encode -> route -> decode contract.
///
/// Deliberately binding-free (no TestWidgetsFlutterBinding), which would
/// otherwise intercept HttpClient and force every call to a 400.
class _CapturingRepo implements LibraryRepository {
  String? deletedItem;
  String? deletedMember;
  String? deletedPrefix;
  String? attrTypeSeen;
  Map<Symbol, Object?>? getItemsArgs;
  Map<Symbol, Object?>? countItemsArgs;
  List<LibraryItem> itemsToReturn = const [];
  int countToReturn = 0;

  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #deleteItem:
        deletedItem = inv.positionalArguments.first as String;
        return Future<void>.value();
      case #deleteMember:
        deletedMember = inv.positionalArguments.first as String;
        return Future<void>.value();
      case #deleteCodeDefinition:
        deletedPrefix = inv.positionalArguments.first as String;
        return Future<void>.value();
      case #getAttributeDefinitions:
        attrTypeSeen = inv.positionalArguments.first as String?;
        return Future<List<Map<String, dynamic>>>.value(const []);
      case #getItems:
        getItemsArgs = {
          #search: inv.namedArguments[#search],
          #status: inv.namedArguments[#status],
          #codeType: inv.namedArguments[#codeType],
          #limit: inv.namedArguments[#limit],
          #offset: inv.namedArguments[#offset],
        };
        return Future<List<LibraryItem>>.value(itemsToReturn);
      case #countItems:
        countItemsArgs = {
          #search: inv.namedArguments[#search],
          #status: inv.namedArguments[#status],
          #codeType: inv.namedArguments[#codeType],
        };
        return Future<int>.value(countToReturn);
    }
    return super.noSuchMethod(inv);
  }
}

void main() {
  late HttpServerService server;
  late _CapturingRepo repo;
  late ApiService api;

  setUp(() async {
    repo = _CapturingRepo();
    server = HttpServerService(repository: repo);
    await server.startServer(host: '127.0.0.1', port: 0);
    api = ApiService(hostIp: '127.0.0.1', port: server.port);
  });

  tearDown(() async {
    await server.stopServer();
  });

  group('API path segments are URL-encoded (FB-04)', () {
    test('an item code with / # ? space and non-ASCII round-trips intact',
        () async {
      const nasty = 'A/B #café?x';
      await api.deleteItem(nasty);
      expect(repo.deletedItem, nasty,
          reason: 'must arrive as ONE decoded segment, not split/404');
    });

    test('a member id with a slash/space round-trips intact', () async {
      const id = 'M-00/01 24';
      await api.deleteMember(id);
      expect(repo.deletedMember, id);
    });

    test('a definition prefix with a slash round-trips intact', () async {
      const prefix = 'LIV/X';
      await api.deleteCodeDefinition(prefix);
      expect(repo.deletedPrefix, prefix);
    });

    test('an attribute type with specials is sent as an encoded query (FB-04)',
        () async {
      const type = 'STATUS/A B';
      await api.getAttributeDefinitions(type);
      expect(repo.attrTypeSeen, type,
          reason: 'query value must arrive decoded, not as STATUS%2FA%20B');
    });
  });

  // FE2-05: a LAN CLIENT must run search/filter/pagination as a SERVER query
  // too -- otherwise its grid can only search the loaded page. This proves the
  // last link of the chain (ApiService builds + percent-encodes the query) by
  // driving the real client against the real server over a socket, with a
  // search term carrying a space, an '&' and a non-ASCII 'é'.
  group('FE2-05: client forwards search/filter to the server query', () {
    test('getItems sends search/status/codeType/limit/offset decoded & intact',
        () async {
      const term = 'Titre 0007 & café';
      final items = await api.getItems(
          limit: 20,
          offset: 40,
          search: term,
          status: 'Emprunté',
          codeType: 'LIV');
      expect(items, isEmpty);
      expect(repo.getItemsArgs, isNotNull,
          reason: 'the /items route must reach the repository with filters');
      expect(repo.getItemsArgs![#search], term,
          reason: 'space/&/é must arrive decoded, not truncated at the &');
      expect(repo.getItemsArgs![#status], 'Emprunté');
      expect(repo.getItemsArgs![#codeType], 'LIV');
      expect(repo.getItemsArgs![#limit], 20);
      expect(repo.getItemsArgs![#offset], 40);
    });

    test('countItems forwards the same filters so page and count agree',
        () async {
      repo.countToReturn = 137;
      final c = await api.countItems(
          search: 'café', status: 'Emprunté', codeType: 'LIV');
      expect(c, 137);
      expect(repo.countItemsArgs![#search], 'café');
      expect(repo.countItemsArgs![#status], 'Emprunté');
      expect(repo.countItemsArgs![#codeType], 'LIV');
    });

    test('a blank search is omitted so it is not applied as a constraint',
        () async {
      await api.getItems(search: '   ');
      expect(repo.getItemsArgs, isNotNull);
      expect(repo.getItemsArgs![#search], isNull,
          reason: 'whitespace-only search must not filter the query');
    });
  });
}
