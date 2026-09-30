import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../models/user_account.dart';
import 'auth_service.dart';

/// Request-context keys the auth middleware populates (Phase 10.1).
const String principalContextKey = 'auth.principal';

/// The identity behind the bearer token of a guarded request, or null when
/// the request came through unauthenticated (bootstrap-open) -- which callers
/// treat as the legacy all-powerful path.
TokenPrincipal? principalOf(Request request) =>
    request.context[principalContextKey] as TokenPrincipal?;

/// Authorization helper for route handlers: true when the request's principal
/// holds at least [minimum]. LEGACY paths -- bootstrap-open (no principal
/// attached) and pre-10.1 unattributed tokens (`isNamed == false`, already
/// admin) -- pass every gate, so enabling roles never strands an existing
/// single-admin install. Least-privilege applies to named accounts only.
bool authorizedFor(Request request, UserRole minimum) {
  final p = principalOf(request);
  if (p == null) return true; // bootstrap-open: no roles configured yet
  if (!p.isNamed) {
    return true; // legacy shared token: keeps its historical rights
  }
  return p.role.atLeast(minimum);
}

/// Builds a shelf [Middleware] that rejects any request lacking a valid bearer
/// token with `401 Unauthorized` (structured JSON), leaving only [openPaths]
/// unauthenticated. A validated token's identity+role is attached to the
/// request context for downstream route guards (Phase 10.1).
///
/// This is the guard that closes NET-01 / SEC-01 (the embedded server currently
/// exposes every route with no authentication). It is intentionally a pure,
/// injectable unit: the running server installs it in a later increment once a
/// credential and the pairing token-exchange ship together, so enabling it does
/// not silently break already-deployed clients.
///
/// Paths are matched against the request's URL path with a leading slash
/// (e.g. `/items`, `/db-version`).
Middleware requireAuth(AuthService auth, {Set<String> openPaths = const {}}) {
  final normalizedOpen = {
    for (final p in openPaths) p.startsWith('/') ? p : '/$p',
  };

  return (Handler innerHandler) {
    return (Request request) async {
      final raw = request.url.path;
      final path = raw.startsWith('/') ? raw : '/$raw';
      if (normalizedOpen.contains(path)) {
        return innerHandler(request);
      }

      final token = _bearerToken(request);
      if (await auth.isAuthorized(token)) {
        final principal = await auth.principalFor(token!);
        return innerHandler(
          request.change(context: {principalContextKey: principal}),
        );
      }

      return Response(
        401,
        body: jsonEncode({
          'error': 'unauthorized',
          'message': 'A valid bearer token is required for this resource.',
        }),
        headers: {'content-type': 'application/json'},
      );
    };
  };
}

/// Same guard as [requireAuth] but with a **bootstrap bypass**: while the host
/// has no admin credential configured, requests pass through untouched.
///
/// This is what makes shipping authentication non-breaking: an existing
/// deployment keeps working exactly as before until the operator sets an admin
/// password, at which point enforcement turns on and only paired/logged-in
/// clients (bearing a token) are served.
Middleware requireAuthIfConfigured(
  AuthService auth, {
  Set<String> openPaths = const {},
}) {
  return (Handler innerHandler) {
    final guarded = requireAuth(auth, openPaths: openPaths)(innerHandler);
    return (Request request) async {
      if (!await auth.enforcementActive()) {
        return innerHandler(request);
      }
      return guarded(request);
    };
  };
}

/// Extracts a `Bearer` token from the `Authorization` header, or `null`.
String? _bearerToken(Request request) {
  final header = request.headers['authorization'];
  if (header == null) return null;
  const prefix = 'bearer ';
  if (header.length <= prefix.length) return null;
  if (header.substring(0, prefix.length).toLowerCase() != prefix) return null;
  final value = header.substring(prefix.length).trim();
  return value.isEmpty ? null : value;
}
