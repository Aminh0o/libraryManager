import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/services/lan_ip.dart';

void main() {
  group('selectLanIp (host address advertised to paired clients)', () {
    test(
      'the regression: a real NIC wins over a VirtualBox host-only adapter',
      () {
        // This is the exact field failure: pairing advertised 192.168.56.1 (the
        // VirtualBox "Host-Only Ethernet Adapter") instead of the routable Wi-Fi
        // address, so a client dialled an interface nothing else could reach.
        const withVirtualFirst = [
          LanInterface(
            name: 'VirtualBox Host-Only Ethernet Adapter',
            address: '192.168.56.1',
          ),
          LanInterface(name: 'Wi-Fi', address: '192.168.1.6'),
        ];
        const withVirtualLast = [
          LanInterface(name: 'Wi-Fi', address: '192.168.1.6'),
          LanInterface(
            name: 'VirtualBox Host-Only Ethernet Adapter',
            address: '192.168.56.1',
          ),
        ];
        expect(selectLanIp(withVirtualFirst), '192.168.1.6');
        expect(
          selectLanIp(withVirtualLast),
          '192.168.1.6',
          reason: 'result must not depend on arrival order',
        );
      },
    );

    test('note that "Ethernet" alone is not virtual — only the markers are', () {
      // A physical "Realtek PCIe GbE Family Controller" and a Hyper-V
      // "vEthernet (Default Switch)" both mention Ethernet-ish words; only the
      // virtual one is demoted.
      const cands = [
        LanInterface(
          name: 'vEthernet (Default Switch)',
          address: '192.168.0.1',
        ),
        LanInterface(
          name: 'Realtek PCIe GbE Family Controller',
          address: '192.168.1.40',
        ),
      ];
      expect(selectLanIp(cands), '192.168.1.40');
    });

    test('a real 10.x NIC beats a 192.168 virtual adapter', () {
      const cands = [
        LanInterface(name: 'VMware Virtual Adapter', address: '192.168.99.1'),
        LanInterface(name: 'Ethernet', address: '10.0.3.7'),
      ];
      expect(selectLanIp(cands), '10.0.3.7');
    });

    test('subnet demotion catches a RENAMED VirtualBox adapter (real machine)', () {
      // The literal field setup: the VirtualBox host-only adapter was renamed to
      // "Ethernet 4" (192.168.56.1), so NO name marker matches — but its known
      // host-only subnet still demotes it below the real "Wi-Fi 2" (192.168.1.2).
      // A Hyper-V "vEthernet (Default Switch)" at 172.28.0.1 is also private and
      // must not win either.
      const cands = [
        LanInterface(name: 'Ethernet 4', address: '192.168.56.1'),
        LanInterface(name: 'vEthernet (Default Switch)', address: '172.28.0.1'),
        LanInterface(name: 'Wi-Fi 2', address: '192.168.1.2'),
      ];
      expect(selectLanIp(cands), '192.168.1.2');
    });

    test(
      'a known virtual subnet alone is still advertised as a last resort',
      () {
        expect(
          selectLanIp(const [
            LanInterface(name: 'Ethernet 4', address: '192.168.56.1'),
          ]),
          '192.168.56.1',
          reason: 'demotion only ranks below a real NIC; never withholds an IP',
        );
      },
    );

    test('loopback and APIPA are never advertised', () {
      expect(
        selectLanIp(const [
          LanInterface(
            name: 'Loopback Pseudo-Interface 1',
            address: '127.0.0.1',
          ),
          LanInterface(name: 'Wi-Fi', address: '169.254.12.9'),
        ]),
        isNull,
        reason: '127/8 and 169.254/16 are unusable host addresses',
      );
    });

    test('empty / no usable candidates -> null', () {
      expect(selectLanIp(const []), isNull);
      expect(
        selectLanIp(const [LanInterface(name: 'x', address: 'not.an.ip')]),
        isNull,
      );
    });

    test('when only virtual addresses exist, still return one (last resort)', () {
      const cands = [
        LanInterface(name: 'Tailscale', address: '100.64.1.2'),
        LanInterface(
          name: 'VirtualBox Host-Only Network',
          address: '192.168.56.1',
        ),
      ];
      // Both are non-routable on the physical LAN, but a value is still better
      // than failing to advertise; 192.168/16 private ranks above a public-ish
      // 100.64 CG-NAT virtual.
      expect(selectLanIp(cands), '192.168.56.1');
    });

    test('multiple real private adapters break ties deterministically by IP', () {
      const a = [
        LanInterface(name: 'Ethernet', address: '192.168.1.50'),
        LanInterface(name: 'Wi-Fi', address: '192.168.1.9'),
      ];
      const b = [
        LanInterface(name: 'Wi-Fi', address: '192.168.1.9'),
        LanInterface(name: 'Ethernet', address: '192.168.1.50'),
      ];
      // Same physical rank + same physical-name bonus -> numeric order decides.
      expect(selectLanIp(a), selectLanIp(b));
      expect(selectLanIp(a), '192.168.1.9'); // lower octets win
    });

    test('isPrivateIpv4 covers the RFC1918 ranges only', () {
      expect(isPrivateIpv4('10.0.0.1'), isTrue);
      expect(isPrivateIpv4('172.16.0.1'), isTrue);
      expect(isPrivateIpv4('172.31.255.255'), isTrue);
      expect(isPrivateIpv4('192.168.0.1'), isTrue);
      expect(isPrivateIpv4('172.15.0.1'), isFalse);
      expect(isPrivateIpv4('172.32.0.1'), isFalse);
      expect(isPrivateIpv4('8.8.8.8'), isFalse);
    });
  });

  group('matchPeerSubnet (DEF-02: answer on the subnet the REQ arrived on)', () {
    // The DEF-02 field shape: host on Wi-Fi 192.168.1.x AND a second LAN
    // (Ethernet / hotspot / host-only) 192.168.43.x; selectLanIp always
    // advertises Wi-Fi, so a client from the second subnet dialled an address
    // it could not route to.
    const host = [
      LanInterface(name: 'Wi-Fi', address: '192.168.1.2'),
      LanInterface(name: 'Ethernet', address: '192.168.43.10'),
    ];

    test('a peer on the secondary subnet gets the secondary host address', () {
      expect(matchPeerSubnet(host, '192.168.43.77'), '192.168.43.10');
      expect(matchPeerSubnet(host, '192.168.1.200'), '192.168.1.2');
    });

    test('no interface on the peer subnet -> null (caller falls back)', () {
      expect(matchPeerSubnet(host, '10.5.5.5'), isNull);
      expect(matchPeerSubnet(const [], '192.168.1.5'), isNull);
    });

    test('non-private or malformed peers never match', () {
      expect(matchPeerSubnet(host, '8.8.8.8'), isNull);
      expect(matchPeerSubnet(host, '127.0.0.1'), isNull);
      expect(matchPeerSubnet(host, 'not-an-ip'), isNull);
      expect(matchPeerSubnet(host, '192.168.1'), isNull);
    });

    test('loopback/APIPA host addresses are never advertised back', () {
      const weird = [
        LanInterface(name: 'Loop', address: '127.0.0.1'),
        LanInterface(name: 'APIPA', address: '169.254.9.9'),
      ];
      expect(matchPeerSubnet(weird, '127.0.0.5'), isNull);
      expect(matchPeerSubnet(weird, '169.254.9.1'), isNull);
    });

    test('a virtual adapter IS selectable when the peer truly lives there', () {
      // Subnet reachability beats the virtual-name demotion: a client on the
      // VirtualBox host-only net can ONLY be reached back via that adapter.
      const cands = [
        LanInterface(name: 'Wi-Fi', address: '192.168.1.2'),
        LanInterface(
          name: 'VirtualBox Host-Only Ethernet Adapter',
          address: '192.168.56.1',
        ),
      ];
      expect(matchPeerSubnet(cands, '192.168.56.40'), '192.168.56.1');
    });

    test('two host addresses on the peer /24 break ties deterministically', () {
      const cands = [
        LanInterface(name: 'Wi-Fi', address: '192.168.43.10'),
        LanInterface(name: 'Hotspot 2', address: '192.168.43.4'),
      ];
      expect(matchPeerSubnet(cands, '192.168.43.99'), '192.168.43.4');
      expect(
        matchPeerSubnet(cands.reversed.toList(), '192.168.43.99'),
        '192.168.43.4',
      );
    });
  });
}
