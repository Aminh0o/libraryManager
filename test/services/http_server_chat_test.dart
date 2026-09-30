import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:library_manager/services/auth_service.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/password_hasher.dart';

import 'http_server_auth_test.dart' show FakeRepo;

/// Phase 19 -- LAN staff chat over a REAL socket, proving the honest bits: the
/// `/chat` routes are staff-only (a viewer/kiosk client is refused before any
/// buffer is touched), a post and its read share ONE authoritative in-process
/// store (so the host's own view and a client's poll never diverge), the
/// since-cursor only ever returns NEW messages, and malformed input is refused
/// rather than silently accepted (empty / over-long are 400, not a fake 201).
void main() {
  late HttpServerService server;
  late AuthService auth;
  late String base;
  late http.Client client;

  setUp(() async {
    auth = AuthService(
      hasher: PasswordHasher(iterations: 1000),
      store: InMemoryAuthStore(),
    );
    server = HttpServerService(repository: FakeRepo(), auth: auth);
    await server.startServer(host: '127.0.0.1', port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = http.Client();
    await auth.setPassword('root-pw');
  });

  tearDown(() async {
    client.close();
    await server.stopServer();
  });

  Future<http.Response> get(String path, {String? token}) => client.get(
      Uri.parse('$base$path'),
      headers: token == null ? {} : {'Authorization': 'Bearer $token'});

  Future<http.Response> post(String path, Map<String, dynamic> body,
          {String? token}) =>
      client.post(Uri.parse('$base$path'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body));

  Future<String> tokenFor(String username, String password) async {
    final res =
        await post('/auth/login', {'username': username, 'password': password});
    expect(res.statusCode, 200, reason: 'login failed for $username');
    return jsonDecode(res.body)['token'] as String;
  }

  Future<String> adminToken() => tokenFor('admin', 'root-pw');

  Future<String> addAndLogin(String name, String pw, String role) async {
    final t = await adminToken();
    final r = await post('/users',
        {'username': name, 'password': pw, 'role': role},
        token: t);
    expect(r.statusCode, 201, reason: 'seed user $name failed: ${r.body}');
    return tokenFor(name, pw);
  }

  Future<http.Response> send(String text, {String? token}) =>
      post('/chat', {'text': text}, token: token);

  test('an unpaired caller cannot read or post chat', () async {
    expect((await get('/chat')).statusCode, 401);
    expect((await send('hi')).statusCode, 401);
  });

  test('a viewer is refused chat read AND write (staff-only surface)', () async {
    final viewer = await addAndLogin('kiosk', 'kiosk-pw-1', 'viewer');
    final r = await get('/chat', token: viewer);
    final w = await send('hello', token: viewer);
    expect(r.statusCode, 403, reason: r.body);
    expect(w.statusCode, 403, reason: w.body);
    expect(jsonDecode(r.body)['error'], 'forbidden');
  });

  test('staff post + read share one store with the host UI', () async {
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final posted = await send('  the printer is jammed  ', token: staff);
    expect(posted.statusCode, 201, reason: posted.body);
    final stored = jsonDecode(posted.body) as Map<String, dynamic>;
    // The server trims surrounding whitespace and attributes the named sender.
    expect(stored['text'], 'the printer is jammed');
    expect(stored['sender'], 'libby');

    // A client poll sees it over HTTP...
    final fetched = await get('/chat?since=0', token: staff);
    expect(fetched.statusCode, 200);
    final msgs =
        (jsonDecode(fetched.body)['messages'] as List<dynamic>).cast<Map>();
    expect(msgs, hasLength(1));
    expect(msgs.first['text'], 'the printer is jammed');

    // ...and so does the host's own in-process view of the SAME buffer.
    final local = server.chatSinceLocal(0);
    expect(local.messages, hasLength(1));
    expect(local.messages.single.text, 'the printer is jammed');
  });

  test('the since-cursor only returns newer messages', () async {
    final admin = await adminToken();
    await send('one', token: admin);
    await send('two', token: admin);
    final first = jsonDecode((await get('/chat', token: admin)).body);
    final cursor = first['latest'] as int;
    expect((first['messages'] as List), hasLength(2));

    await send('three', token: admin);
    final second =
        jsonDecode((await get('/chat?since=$cursor', token: admin)).body);
    final newer = (second['messages'] as List<dynamic>).cast<Map>();
    expect(newer, hasLength(1));
    expect(newer.single['text'], 'three');
  });

  test('a host-local post reaches the client poll (one transcript)', () async {
    server.postChatLocal('admin', 'admin', 'from the host');
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    final res = await get('/chat?since=0', token: staff);
    final msgs = (jsonDecode(res.body)['messages'] as List<dynamic>).cast<Map>();
    expect(msgs, hasLength(1));
    expect(msgs.single['text'], 'from the host');
    expect(msgs.single['sender'], 'admin');
  });

  test('empty and over-long messages are refused, never fake-accepted',
      () async {
    final staff = await addAndLogin('libby', 'libby-pw-1', 'staff');
    expect((await send('   ', token: staff)).statusCode, 400);
    expect((await send('', token: staff)).statusCode, 400);
    expect((await send('x' * 1001, token: staff)).statusCode, 400);
    // A valid-length message still succeeds, so the guard is a bound not a ban.
    expect((await send('x' * 1000, token: staff)).statusCode, 201);
  });
}
