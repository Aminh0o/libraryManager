/// Single source of truth for the LAN networking defaults (ARC-05 / DEP).
///
/// The HTTP API port and the UDP pairing port used to be scattered as bare
/// `8080` / `19001` literals across the server bind, the client default, the
/// pairing response and the Windows firewall rules. Any one of them drifting
/// silently broke pairing/discovery, and the literals made it impossible to run
/// host+client integration tests on ephemeral ports. The values themselves are
/// unchanged (a client still defaults to 8080 / pairing to 19001); what changed
/// is that every default now resolves from here, so there is exactly one place
/// to reason about -- and a real bound port, once learned from the pairing
/// response, still overrides these defaults everywhere (NET-01).
class NetworkConfig {
  // Not instantiable; this is a namespace for shared constants.
  NetworkConfig._();

  /// Default TCP port the embedded LAN HTTP server binds, and the port a client
  /// assumes before it learns the host's actual port via pairing.
  static const int defaultHttpPort = 8080;

  /// Default UDP port used for LAN pairing discovery (broadcast/unicast probe).
  static const int defaultPairingUdpPort = 19001;
}
