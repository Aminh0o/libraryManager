// LAN pairing wire format, kept framework-free and pure so both directions
// are unit-testable without any UDP socket and the host + client cannot drift
// on the encoding (NET-01: the response carries the host's REAL bound port).
//
// * Request  (client -> host, broadcast): `LIB_PAIR_REQ:<code>`
// * Response (host -> client, unicast):
//   `LIB_PAIR_RESP:<code>:<ip>:<port>:<expiresEpochMs>[:<token>]`
//
// The optional 6th field carries a bearer token issued by the host so a
// paired client never sends the admin password on the wire (SEC-01).

const String pairingReqPrefix = 'LIB_PAIR_REQ:';
const String pairingRespPrefix = 'LIB_PAIR_RESP:';

/// Builds a pairing response advertising [port]. [token] is optional; empty
/// omits the trailing field, matching responses minted before bearer tokens.
String encodePairingResponse({
  required String code,
  required String ip,
  required int port,
  required int expiresEpochMs,
  String token = '',
}) {
  final base = '$pairingRespPrefix$code:$ip:$port:$expiresEpochMs';
  return token.isEmpty ? base : '$base:$token';
}

/// A successfully decoded pairing response.
class PairingResponse {
  const PairingResponse({required this.ip, required this.port, this.token});
  final String ip;
  final int port;
  final String? token;
}

/// Parses a pairing [datagram]. Returns `null` unless it is a well-formed
/// response whose code equals [expectedCode] and whose expiry is still in the
/// future relative to [now]. The advertised [PairingResponse.port] is accepted
/// as any valid TCP port — no longer pinned to 8080 (NET-01).
PairingResponse? decodePairingResponse(
  String datagram, {
  required String expectedCode,
  required DateTime now,
}) {
  if (!datagram.startsWith(pairingRespPrefix)) return null;
  final parts = datagram.split(':');
  if (parts.length < 5) return null;

  final respCode = parts[1].trim();
  final ip = parts[2].trim();
  final port = int.tryParse(parts[3].trim());
  final expiresEpochMs = int.tryParse(parts[4].trim());

  if (respCode != expectedCode) return null;
  if (port == null || port <= 0 || port > 65535) return null;
  if (expiresEpochMs == null) return null;
  if (ip.isEmpty) return null;
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresEpochMs);
  if (now.isAfter(expiresAt)) return null;

  String? token;
  if (parts.length >= 6) {
    final t = parts[5].trim();
    if (t.isNotEmpty) token = t;
  }
  return PairingResponse(ip: ip, port: port, token: token);
}

// ---------------------------------------------------------------------------
// Host-screen pairing QR (DEF-03)
//
// * QR payload (host screen -> client camera): `LIB_SYNC:<ip>[:<port>]`
//
// The UDP pairing response learned to carry the host's REAL bound port
// (NET-01) but the QR beside it still advertised only the IP, so a client on
// a machine where 8080 was taken dialed the default and failed with no
// obvious cause. The port is now embedded; the 1-field legacy form stays
// decodable so phones that scanned an older screen keep working (the client
// then falls back to the default port, exactly the old behavior).
// ---------------------------------------------------------------------------

const String pairingQrPrefix = 'LIB_SYNC:';

/// A decoded host pairing QR: the address to dial and, when the payload
/// carried one, the host's actual bound port (null = use the default).
class PairingQr {
  const PairingQr({required this.ip, this.port});
  final String ip;
  final int? port;
}

/// Builds the QR payload for the host screen (DEF-03: always carries the
/// port the server actually bound).
String encodePairingQr({required String ip, required int port}) =>
    '$pairingQrPrefix$ip:$port';

/// Parses a scanned pairing QR. Returns `null` for anything that is not a
/// well-formed `LIB_SYNC:` payload — wrong scheme, blank/whitespace host, an
/// out-of-range or non-numeric port, or extra fields — so the caller can
/// show an actionable message instead of swallowing the scan.
PairingQr? decodePairingQr(String payload) {
  if (!payload.startsWith(pairingQrPrefix)) return null;
  final rest = payload.substring(pairingQrPrefix.length);
  final parts = rest.split(':');
  if (parts.length > 2) return null;
  final ip = parts[0].trim();
  if (ip.isEmpty || ip.contains(RegExp(r'\s')) || ip.length > 253) return null;
  int? port;
  if (parts.length == 2) {
    port = int.tryParse(parts[1].trim());
    if (port == null || port <= 0 || port > 65535) return null;
  }
  return PairingQr(ip: ip, port: port);
}
