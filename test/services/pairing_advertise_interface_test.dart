// Phase 4 (P1 LAN blocker) — reproduction of the owner-reported "pairing
// never works across Wi-Fi / Ethernet / phone hotspot" family, run over REAL
// UDP against the REAL provider responder.
//
// The hazard: the host advertises ONE globally-ranked LAN address
// (selectLanIp) in every pairing response, regardless of WHICH of its
// interfaces the client's REQ actually arrived on. A machine joined to two
// subnets at once (Wi-Fi 192.168.1.x + Ethernet/hotspot/host-only
// 192.168.56.x) answers a client on the second subnet with an address on the
// FIRST one — which that client cannot route to. The socket is up, the code
// is right, the token is issued, and the client still fails to connect:
// exactly the field symptom.
//
// This machine simulates the second subnet by sending the REQ from its own
// secondary interface address (same-host delivery preserves the source IP,
// so the responder sees a peer living on a different /24). A two-machine
// retest across real Wi-Fi/Ethernet/hotspot remains NOT EXECUTED (one
// developer machine only) — see LAN_DIAGNOSTICS_AND_TEST_RESULTS.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/config/network_config.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/http_server_service.dart';
import 'package:library_manager/services/pairing_protocol.dart';
import 'package:library_manager/services/repository.dart';

class _NullRepo implements LibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Stub whose `port` is a fixed real value, standing in for the HTTP server
/// the responder advertises alongside the IP (the subject here is the IP).
class _StubServer extends HttpServerService {
  _StubServer(this._boundPort) : super(repository: _NullRepo());
  final int _boundPort;

  @override
  bool get isRunning => true;

  @override
  int get port => _boundPort;

  @override
  Future<void> startServer({
    Function(String ip)? onActivity,
    String host = '0.0.0.0',
    int port = 8080,
  }) async {}
}

bool _isPrivate(String ip) {
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('192.168.')) return true;
  final o = ip.split('.');
  if (o.length == 4) {
    final a = int.tryParse(o[0]);
    final b = int.tryParse(o[1]);
    if (a == 172 && b != null && b >= 16 && b <= 31) return true;
  }
  return false;
}

String _subnet(String ip) => ip.split('.').take(3).join('.');

void main() async {
  // Async collection BEFORE registration so `skip` can be a real decision:
  // the socket proof needs a host with two private IPv4 addresses on
  // different /24s. On a single-subnet machine this stays explicitly skipped
  // (visible, not silently passing).
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
    type: InternetAddressType.IPv4,
  ).catchError((_) => <NetworkInterface>[]);
  final bySubnet = <String, String>{};
  for (final ni in interfaces) {
    for (final addr in ni.addresses) {
      final ip = addr.address;
      if (addr.type == InternetAddressType.IPv4 && _isPrivate(ip)) {
        bySubnet.putIfAbsent(_subnet(ip), () => ip);
      }
    }
  }
  final twoSubnets = bySubnet.length >= 2;
  // The client stand-in uses a private subnet OTHER than the loopback-free
  // primary; on this dev machine the candidates are Wi-Fi 192.168.1.2 and a
  // VirtualBox host-only 192.168.56.1, and selectLanIp globally advertises
  // the Wi-Fi one — so a peer bound to .56 exercises the cross-subnet case.
  final secondary = bySubnet.values.toList()..sort();

  // No TestWidgetsFlutterBinding: like the concurrency register, this drives
  // real sockets binding-free (the binding's HttpOverrides would fake-out IO).

  test('REPRO DEF-02: a pairing REQ arriving on a secondary subnet is answered '
      'with an address the requester can actually route to', () async {
    final provider = LibraryProvider.forTesting(repository: _NullRepo());
    provider.serverForTesting = _StubServer(8080);
    final code = await provider.startPairingCode();
    final globalIp = await provider.getLocalIp();
    expect(globalIp, isNotNull, reason: 'no LAN IPv4 on this machine');

    // "Client" on a subnet the GLOBAL advertisement does NOT live on: bind
    // to that source address and unicast the REQ to the host's responder on
    // this machine (same-host delivery preserves the source IP, which is
    // the whole point).
    final peerIp = secondary.firstWhere(
      (ip) => _subnet(ip) != _subnet(globalIp!),
      orElse: () => throw StateError(
        'every private subnet on this host equals the advertised one ($globalIp)',
      ),
    );
    final client = await RawDatagramSocket.bind(
      InternetAddress(peerIp),
      0,
      reuseAddress: true,
    );
    final done = Completer<String>();
    client.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = client.receive();
      if (dg != null && !done.isCompleted) {
        done.complete(String.fromCharCodes(dg.data));
      }
    });
    client.send(
      'LIB_PAIR_REQ:$code'.codeUnits,
      InternetAddress(peerIp),
      NetworkConfig.defaultPairingUdpPort,
    );

    final datagram = await done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError(
        'no pairing response within 5s (peer subnet $peerIp)',
      ),
    );
    client.close();
    provider.dispose();

    final resp = decodePairingResponse(
      datagram,
      expectedCode: code,
      now: DateTime.now(),
    );
    expect(resp, isNotNull, reason: 'response malformed: $datagram');

    // The decisive property: the advertised address must live on the
    // subnet the request arrived from, or the paired client dials an
    // address it cannot route to.
    expect(
      _subnet(resp!.ip),
      _subnet(peerIp),
      reason:
          'REQ arrived from $peerIp (${_subnet(peerIp)}.x) but the host '
          'advertised ${resp.ip} — a client on that subnet cannot reach it',
    );
  }, skip: twoSubnets ? false : 'needs two private IPv4 subnets on this host');

  test(
    'a REQ arriving on the globally-advertised subnet still gets that address '
    '(no regression for the normal single-LAN case)',
    () async {
      final provider = LibraryProvider.forTesting(repository: _NullRepo());
      provider.serverForTesting = _StubServer(8080);
      final code = await provider.startPairingCode();
      final globalIp = await provider.getLocalIp();
      if (globalIp == null) {
        throw StateError('no LAN IPv4 to test against on this machine');
      }

      final client = await RawDatagramSocket.bind(
        InternetAddress(globalIp),
        0,
        reuseAddress: true,
      );
      final done = Completer<String>();
      client.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = client.receive();
        if (dg != null && !done.isCompleted) {
          done.complete(String.fromCharCodes(dg.data));
        }
      });
      client.send(
        'LIB_PAIR_REQ:$code'.codeUnits,
        InternetAddress(globalIp),
        NetworkConfig.defaultPairingUdpPort,
      );

      final datagram = await done.future.timeout(const Duration(seconds: 5));
      client.close();
      provider.dispose();

      final resp = decodePairingResponse(
        datagram,
        expectedCode: code,
        now: DateTime.now(),
      );
      expect(resp, isNotNull);
      expect(resp!.ip, globalIp);
      expect(resp.port, 8080);
    },
  );
}
