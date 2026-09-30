// Pure LAN/API protocol-version contract shared by the host server and the
// client. No Flutter / I/O dependencies so it is trivially unit-testable and can
// be imported by both sides of the repository seam.

import '../models/user_account.dart';

/// LAN/API protocol version. The host server and the client are compiled from
/// the SAME Flutter binary, so in a fully-upgraded deployment they always agree.
/// This constant exists so a PARTIAL upgrade -- a stale `library_manager.exe`
/// client talking to a newer host (or the reverse) -- is DETECTED and refused
/// instead of silently mis-parsing responses and corrupting data (DEP-02).
///
/// Bump whenever the wire contract changes in a way an older peer cannot safely
/// handle: a removed/renamed field, a changed request/response shape, a new
/// required header, or altered status-code semantics. Purely additive,
/// backward-compatible changes do NOT require a bump.
const int kApiProtocolVersion = 1;

/// Header every client sends advertising the protocol it speaks. The server
/// rejects (426) a request that carries this header with an incompatible value,
/// while still accepting requests that omit it (legacy peers, curl, health
/// probes) so introducing versioning never breaks an already-deployed client.
const String apiVersionHeader = 'X-Api-Version';

/// Numeric field the server adds to the `/db-version` response so a client can
/// learn the host's protocol on its very first (and every subsequent) poll.
const String apiVersionBodyKey = 'api';

/// True only when [serverVersion] is exactly this build's protocol. A `null`
/// (a server that predates versioning and never sent the field) counts as
/// INCOMPATIBLE, so an unknown contract is never silently trusted.
bool isApiVersionCompatible(int? serverVersion) =>
    serverVersion == kApiProtocolVersion;

/// A successful `POST /auth/login` result (Phase 10.1). The client uses it to
/// label WHO it is signed in as and to gate write affordances DYNAMICALLY;
/// the server stays the enforcement authority regardless, so a stale or
/// tampered client view can only ever be refused a 403, never escalate.
///
/// A response with no `role` (an older host, or a hand-rolled body) resolves to
/// the LEAST privileged role rather than guessing admin.
class LoginSession {
  const LoginSession({
    required this.token,
    required this.username,
    required this.role,
  });

  final String token;
  final String username;
  final UserRole role;

  factory LoginSession.fromJson(Map<String, dynamic> json) => LoginSession(
        token: (json['token'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        role: UserRole.tryParse(json['role']) ?? UserRole.viewer,
      );

  bool get isValid => token.isNotEmpty;
}
