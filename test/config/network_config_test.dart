import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/config/network_config.dart';
import 'package:library_manager/services/api_service.dart';

/// ARC-05 / DEP: the LAN HTTP port and the UDP pairing port used to be scattered
/// as bare `8080` / `19001` literals across the server bind, the client default,
/// the pairing response and the firewall rules. Any one of them drifting silently
/// broke pairing, and the literals made ephemeral-port integration testing
/// impossible. These tests pin the interop contract (the defaults must stay the
/// wire values already-deployed peers expect), prove the client default now
/// resolves from the single config source, and scan the whole `lib/` tree so a
/// bare numeric port DEFAULT can never reappear outside `network_config.dart`.
void main() {
  group('NetworkConfig single source of truth (ARC-05 / DEP)', () {
    test('defaults keep the documented wire values (interop guard)', () {
      // Already-deployed clients and the firewall rules assume these; changing
      // them silently breaks pairing, so an edit here must be deliberate.
      expect(NetworkConfig.defaultHttpPort, 8080);
      expect(NetworkConfig.defaultPairingUdpPort, 19001);
    });

    test('ApiService default port resolves from the shared config', () {
      final svc = ApiService(hostIp: '127.0.0.1');
      expect(svc.port, NetworkConfig.defaultHttpPort);
      svc.close();
    });

    test('no bare port-default literal survives outside the config source', () {
      // Walk every production Dart file; a numeric 8080/19001 token is allowed
      // only inside comments, inside the firewall display-name label constants,
      // or in network_config.dart itself (the single source). Any other hit is a
      // re-scattered magic number.
      final lib = Directory('lib');
      expect(
        lib.existsSync(),
        isTrue,
        reason: 'run from the package root so lib/ is reachable',
      );
      final portToken = RegExp(r'(?<![0-9])(?:8080|19001)(?![0-9])');
      final offenders = <String>[];
      for (final entity in lib.listSync(recursive: true).whereType<File>()) {
        if (!entity.path.endsWith('.dart')) continue;
        final isConfig = entity.uri.pathSegments.contains(
          'network_config.dart',
        );
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!portToken.hasMatch(line)) continue;
          final t = line.trim();
          final isComment =
              t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
          // Stable firewall rule DISPLAY names legitimately embed the default
          // port as a label; the real port the rule opens comes from config.
          final isRuleLabel = t.contains('Library Manager LAN');
          if (isConfig || isComment || isRuleLabel) continue;
          offenders.add('${entity.path}:${i + 1}: $t');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'bare port literals must resolve from NetworkConfig:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
