import 'package:flutter_test/flutter_test.dart';

import 'package:library_manager/models/library_item.dart';
import 'package:library_manager/models/loan.dart';
import 'package:library_manager/models/member.dart';
import 'package:library_manager/providers/library_provider.dart';
import 'package:library_manager/services/repository.dart';

// NET-07: a CLIENT used to hold a confident green 'Connected' for the whole
// 12-second give-up grace window after the LAN dropped, hiding the outage. The
// fix exposes a tri-state connectionStatus that turns amber on the FIRST
// failed probe. These tests drive the SAME probe accounting the periodic
// health check runs (via clientProbeForTesting -> _onClientProbeFailure), so
// they prove the real transitions, not a re-implementation.
class _EmptyRepo implements LibraryRepository {
  @override
  Future<List<LibraryItem>> getItems({
    int limit = 1000,
    int offset = 0,
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => const [];
  @override
  Future<int> countItems({
    String? search,
    String? status,
    String? codeType,
    String? sort,
    bool ascending = true,
  }) async => 0;
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(
    String? type,
  ) async => const [];
  @override
  Future<Map<String, dynamic>> getStats() async => const {};
  @override
  Future<List<Member>> getMembers() async => const [];
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test(
    'client turns RECONNECTING on the first failed probe (not a false green)',
    () async {
      final provider = LibraryProvider.forTesting(
        repository: _EmptyRepo(),
        isHost: false,
      );

      await provider.clientProbeForTesting(success: true, version: '1');
      expect(provider.connectionStatus, LanConnectionStatus.connected);
      expect(provider.isConnected, isTrue);

      // ONE blip: still nominally connected, but the header must go amber NOW.
      await provider.clientProbeForTesting(success: false);
      expect(provider.isConnected, isTrue); // grace window not exhausted
      expect(provider.connectionStatus, LanConnectionStatus.reconnecting);
    },
  );

  test('client recovers to CONNECTED once a probe succeeds again', () async {
    final provider = LibraryProvider.forTesting(
      repository: _EmptyRepo(),
      isHost: false,
    );
    await provider.clientProbeForTesting(success: true, version: '1');
    await provider.clientProbeForTesting(success: false);
    expect(provider.connectionStatus, LanConnectionStatus.reconnecting);

    await provider.clientProbeForTesting(success: true, version: '1');
    expect(provider.connectionStatus, LanConnectionStatus.connected);
  });

  test(
    'client only drops to DISCONNECTED after the grace window expires',
    () async {
      final provider = LibraryProvider.forTesting(
        repository: _EmptyRepo(),
        isHost: false,
      );
      await provider.clientProbeForTesting(success: true, version: '1');

      // Back-date the last success past the 12s window, then fail 3 probes.
      provider.lastHealthSuccessForTesting = DateTime.now().subtract(
        const Duration(seconds: 13),
      );
      await provider.clientProbeForTesting(success: false);
      await provider.clientProbeForTesting(success: false);
      expect(
        provider.connectionStatus,
        LanConnectionStatus.reconnecting,
      ); // 2 fails

      await provider.clientProbeForTesting(success: false); // 3rd, now too old
      expect(provider.isConnected, isFalse);
      expect(provider.connectionStatus, LanConnectionStatus.disconnected);
    },
  );

  test('a HOST never shows the client-only amber state', () async {
    final provider = LibraryProvider.forTesting(
      repository: _EmptyRepo(),
      isHost: true,
    );
    await provider.clientProbeForTesting(success: true, version: '1');
    expect(provider.connectionStatus, LanConnectionStatus.connected);

    // A host is LAN-local; amber 'reconnecting' is guarded to clients only.
    await provider.clientProbeForTesting(success: false);
    expect(provider.connectionStatus, LanConnectionStatus.connected);
  });
}
