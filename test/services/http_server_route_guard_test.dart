import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';

/// Phase 10 -- ROUTE-GUARD COMPLETENESS (static).
///
/// The socket tests (`http_server_roles_test.dart`) prove representative routes
/// refuse the wrong role. This test proves the STRUCTURAL invariant those tests
/// cannot: that EVERY mutating route in the server registers an authorization
/// check before doing any work, so a future `router.post/put/delete` added
/// without a guard fails the build instead of silently shipping an
/// unenforced endpoint.
///
/// It scans the real source, not a mirror, so it fails the moment the file and
/// the invariant drift apart.
void main() {
  group('every mutating HTTP route enforces a role gate', () {
    final source = File('lib/services/http_server_service.dart');

    test('the server source is readable from the package root', () {
      expect(
        source.existsSync(),
        isTrue,
        reason: 'run tests from the package root',
      );
    });

    test('each POST/PUT/DELETE/PATCH handler registers _forbiddenUnless', () {
      final lines = source.readAsLinesSync();

      // Index of every route registration line (any verb) so a handler's body
      // is exactly the span from its own registration to the next one.
      final regIndex = <int>[];
      final routeLine = RegExp(
        r"""router\.(get|post|put|delete|patch)\(\s*'([^']+)'""",
      );
      final regs = <_Reg>[];
      for (var i = 0; i < lines.length; i++) {
        final m = routeLine.firstMatch(lines[i]);
        if (m != null) {
          regIndex.add(i);
          regs.add(_Reg(verb: m.group(1)!, path: m.group(2)!, line: i));
        }
      }
      expect(regs, isNotEmpty);

      // The single intentional exception: the login endpoint is how a caller
      // obtains a token in the first place, so it cannot itself demand one. It
      // is still covered by the bearer/auth layer + PairingGuard rate limits.
      const unguardedAllowed = {'/auth/login', '/auth/pair'};

      final violations = <String>[];
      for (final r in regs) {
        if (r.verb == 'get') continue; // reads gated separately / open reads
        final next = regIndex.firstWhere(
          (i) => i > r.line,
          orElse: () => lines.length,
        );
        final body = lines.sublist(r.line, next).join('\n');
        final guarded = body.contains('_forbiddenUnless');
        if (!guarded && !unguardedAllowed.contains(r.path)) {
          violations.add(
            '${r.verb.toUpperCase()} ${r.path} (line ${r.line + 1})',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'mutating route(s) without a _forbiddenUnless role gate: $violations',
      );
    });
  });
}

class _Reg {
  const _Reg({required this.verb, required this.path, required this.line});
  final String verb;
  final String path;
  final int line;
}
