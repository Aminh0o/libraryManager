// LAN host-address selection, kept framework-free and pure so it is unit-testable
// without any socket or a live NetworkInterface.list.
//
// Why this exists: the pairing responder advertises the host's LAN IPv4 to the
// client (the address the client then dials on the real port). The old code took
// `NetworkInterface.list(...)` and returned the first RFC1918 address it saw.
// `list` has no guaranteed ordering and a machine routinely has several private
// IPv4 addresses — a real Wi-Fi/Ethernet NIC *and* virtual adapters (VirtualBox
// "Host-Only", VMware, Hyper-V "vEthernet", Tailscale, TAP, …). Picking `.first`
// nonchalantly advertised a host-only virtual address such as 192.168.56.1, so a
// paired client was pointed at an interface no other machine on the LAN could
// route to — pairing "never worked" even though every socket was up. Ranking by
// interface character instead of arrival order fixes that deterministically.

/// One candidate interface/address for [selectLanIp]. [name] is the adapter's
/// (friendly) name as reported by the OS; [address] is an IPv4 dotted quad.
class LanInterface {
  const LanInterface({required this.name, required this.address});
  final String name;
  final String address;
}

/// Adapter names that are (almost) never the machine's real LAN uplink. Matched
/// case-insensitively as substrings. Chosen conservatively: a false "virtual"
/// hit only demotes an interface, it never invents one, and a real adapter whose
/// name trips no rule still wins on rank 0.
const List<String> _virtualNameMarkers = <String>[
  'virtualbox',
  'vmware',
  'vethernet',
  'hyper-v',
  'hyperv',
  'host-only',
  'loopback',
  'loop back',
  'tap-',
  'tap adapter',
  'tap-tunnel',
  'wintun',
  'tailscale',
  'zerotier',
  'hamachi',
  'anyconnect',
  'bluetooth',
  'isatap',
  'teredo',
  'docker',
  'wsl',
  'container',
  'pnat',
  'nat',
  'pseudo',
  'miniport',
];

/// Names that, all else equal, most likely denote a genuine physical uplink.
/// Used only as a tie-breaker within the top rank, never to promote an address
/// over a non-virtual interface.
const List<String> _physicalNameMarkers = <String>[
  'wi-fi',
  'wifi',
  'wlan',
  'ethernet',
  'eth',
  'gigabit',
  'realtek',
  'intel',
  'killer',
  'broadcom',
  'atheros',
  'local area',
];

/// Well-known private ranges that overwhelmingly belong to a *virtual*
/// host-only / switch network rather than a routable physical LAN, matched
/// independently of the adapter name (a user can rename "VirtualBox Host-Only"
/// to "Ethernet 4", defeating the name blacklist, but not its subnet). These
/// are only ever a demotion — never a reason to withhold an address entirely.
bool _isKnownVirtualSubnet(String ip) {
  final o = ip.split('.');
  if (o.length != 4) return false;
  final a = int.tryParse(o[0]);
  final b = int.tryParse(o[1]);
  final c = int.tryParse(o[2]);
  if (a == null || b == null || c == null) return false;
  // VirtualBox host-only default is 192.168.56.0/24.
  if (a == 192 && b == 168 && c == 56) return true;
  // Tailscale / CGNAT 100.64.0.0/10 (100.64 – 100.127 in the 2nd octet).
  if (a == 100 && b >= 64 && b <= 127) return true;
  return false;
}

bool _containsAny(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}

/// RFC1918 private address test (the LAN ranges a client can actually reach).
bool isPrivateIpv4(String ip) {
  if (ip.startsWith('10.')) return true;
  if (ip.startsWith('192.168.')) return true;
  final parts = ip.split('.');
  if (parts.length == 4) {
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == 172 && second != null && second >= 16 && second <= 31) {
      return true;
    }
  }
  return false;
}

/// A usable host address is a well-formed, non-loopback, non-link-local IPv4.
/// APIPA (169.254/16) is dropped: it means "no DHCP/DNS was obtained" and is
/// useless to advertise, and 127/8 + 0.0.0.0 are self/non-addresses.
bool _isUsableIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null || v < 0 || v > 255) return false;
    octets.add(v);
  }
  if (octets[0] == 127) return false; // loopback
  if (octets[0] == 169 && octets[1] == 254) return false; // APIPA
  if (octets[0] == 0) return false; // this-network / unspecified
  return true;
}

/// Rank a candidate: lower is better.
/// 0 = private, non-virtual (the real LAN uplink — what we advertise)
/// 1 = public, non-virtual (a directly-routed non-RFC1918 NIC)
/// 2 = private, virtual (VirtualBox host-only, Hyper-V, …) — last resort
/// 3 = public, virtual
///
/// "Virtual" is decided by EITHER a name marker OR a known virtual subnet, so a
/// renamed "Ethernet 4" carrying 192.168.56.1 is still demoted below the real
/// Wi-Fi address.
int _rank(LanInterface i, String lowerName) {
  final priv = isPrivateIpv4(i.address);
  final virt =
      _containsAny(lowerName, _virtualNameMarkers) ||
      _isKnownVirtualSubnet(i.address);
  if (priv && !virt) return 0;
  if (!priv && !virt) return 1;
  if (priv && virt) return 2;
  return 3;
}

/// Secondary sort within a rank: prefer a physical-sounding adapter name; then a
/// deterministic numeric-IP order so the result never depends on arrival order.
int _physicalBonus(String lowerName) =>
    _containsAny(lowerName, _physicalNameMarkers) ? 0 : 1;

int _compareOctets(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 4; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Chooses the address to advertise as this machine's LAN host. Returns the
/// highest-ranked candidate, or `null` when none is usable. Deterministic: the
/// same input list always yields the same output regardless of ordering.
String? selectLanIp(List<LanInterface> interfaces) {
  final scored = <_Scored>[];
  for (final i in interfaces) {
    if (!_isUsableIpv4(i.address)) continue;
    final lower = i.name.toLowerCase();
    scored.add(
      _Scored(
        ip: i.address,
        rank: _rank(i, lower),
        bonus: _physicalBonus(lower),
      ),
    );
  }
  if (scored.isEmpty) return null;
  scored.sort((a, b) {
    final r = a.rank.compareTo(b.rank);
    if (r != 0) return r;
    final bo = a.bonus.compareTo(b.bonus);
    if (bo != 0) return bo;
    return _compareOctets(a.ip, b.ip);
  });
  return scored.first.ip;
}

class _Scored {
  const _Scored({required this.ip, required this.rank, required this.bonus});
  final String ip;
  final int rank;
  final int bonus;
}

/// Picks the host interface address that lives on the SAME /24 as [peerIp] —
/// the address a pairing REQ came in on. Returns `null` when no candidate
/// shares the peer's subnet, so the caller falls back to the globally-ranked
/// [selectLanIp] advertisement (the pre-DEF-02 behavior).
///
/// Why this exists (DEF-02, the owner-reported "pairing fails across PCs /
/// Wi-Fi / Ethernet / phone hotspot"): a host joined to several subnets at
/// once answers every pairing REQ with ONE globally-ranked address, whatever
/// interface the request arrived on. A client on the *second* subnet then
/// dials an address it cannot route to — sockets up, code right, connection
/// still dead. The REQ itself proves which of the host's subnets the client
/// can reach (it delivered a packet there), so answering on that subnet is
/// always the reachable choice. Virtual adapters are NOT demoted here: a
/// peer that really lives on a host-only/virtual subnet can only be reached
/// back through that same interface, so the subnet match outranks every
/// other heuristic.
String? matchPeerSubnet(List<LanInterface> interfaces, String peerIp) {
  final p = peerIp.split('.');
  if (p.length != 4) return null;
  if (p.any((o) => int.tryParse(o) == null)) return null;
  if (!isPrivateIpv4(peerIp)) return null;
  final prefix = '${p[0]}.${p[1]}.${p[2]}';
  final matches = <String>[];
  for (final i in interfaces) {
    if (!_isUsableIpv4(i.address)) continue;
    final o = i.address.split('.');
    if (o.length != 4) continue;
    if ('${o[0]}.${o[1]}.${o[2]}' == prefix) matches.add(i.address);
  }
  if (matches.isEmpty) return null;
  matches.sort(_compareOctets);
  return matches.first;
}
