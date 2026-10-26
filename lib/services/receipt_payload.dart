/// PRINT-QR / circulation-slip payload codec (commercial hardening §6.12).
///
/// A QR printed on a loan / return / renewal / hold slip or a member card is a
/// *record identifier*, NOT an action trigger and NOT the LAN-pairing code.
/// This module keeps those three concerns strictly separate:
///
///  * The LAN pairing QR (`LIB_SYNC:<ip>[:<port>]`, built in `settings_screen.dart`) is a
///    different subsystem; [isPairingPayload] recognises it so a receipt scanner
///    never mistakes a pairing code for a record and vice-versa (§282).
///  * A printed payload carries ONLY a version tag, a document type and an
///    opaque reference (§284). It never embeds a member name, e-mail, phone,
///    fine balance, a credential, a bearer token or a pairing secret. The
///    reference is whatever stable, non-enumerable id the caller already has
///    (a loan row id, or the member card id) — callers MUST NOT pass PII.
///  * Decoding is STRICT (the two-parser discipline used across the domain
///    models): malformed / unknown-version / unknown-type input yields `null`,
///    it is never guessed. Callers resolve `null` to "not a Library Manager
///    record code" and must not mutate anything (§286).
///
/// This file is deliberately framework-free (no Flutter / DB / socket imports)
/// so host, client and pure unit tests share one definition.
library;

import 'dart:convert';

/// Document kinds a printed code may identify. Codes on the wire use the
/// [ReceiptDocType.code] short form, never the Dart name, so the enum can be
/// reordered without breaking already-printed slips (§289 backward-compat).
enum ReceiptDocType {
  loan('LOAN'),
  return_('RET'),
  renewal('REN'),
  hold('HOLD'),
  card('CARD');

  const ReceiptDocType(this.code);

  /// Stable short token embedded in the payload. Frozen — never reuse for a
  /// different meaning across releases.
  final String code;

  static ReceiptDocType? fromCode(String code) {
    for (final t in ReceiptDocType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Current payload format version. Bump only with an explicit, documented
/// migration; older clients must reject an unknown version rather than act on
/// it (§285 "reject ... unknown-version ... payloads safely").
const int kReceiptPayloadVersion = 1;

/// The prefix that identifies a Library Manager *receipt* QR, as distinct from
/// the `LIB_SYNC:` LAN-pairing QR.
const String kReceiptScheme = 'LM1';

/// Separator between the scheme, the document-type code and the reference. A
/// pipe is used so it can never collide with an IPv4 address / URL inside the
/// pairing payload's colon-delimited format.
const String _sep = '|';

/// The prefix the existing LAN-pairing QR uses (kept here only so receipt tooling
/// can positively identify-and-ignore it). Not a receipt format.
const String kPairingPrefix = 'LIB_SYNC:';

/// Thrown when [encodeReceiptPayload] is given a reference that cannot safely be
/// embedded (empty, over-long, or carrying characters outside the conservative
/// opaque-id alphabet). Callers fix the input rather than silently truncate it.
class ReceiptPayloadException implements Exception {
  const ReceiptPayloadException(this.message);
  final String message;
  @override
  String toString() => 'ReceiptPayloadException: $message';
}

/// Allowed opaque-reference characters: letters, digits, dash and underscore.
/// Deliberately excludes `|`, `:`, spaces, control characters and any accent so
/// the reference can neither inject a second field nor smuggle free-text PII.
final RegExp _refPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// A decoded, validated receipt code. Immutable value object.
class ReceiptPayload {
  const ReceiptPayload({
    required this.version,
    required this.type,
    required this.ref,
  });

  final int version;
  final ReceiptDocType type;

  /// The opaque record reference. NOT PII; resolve it through the normal
  /// authenticated domain path, never act on the raw string alone.
  final String ref;

  /// Re-serialises to the canonical wire form.
  String encode() => '$kReceiptScheme$_sep${type.code}$_sep$ref';

  @override
  String toString() => 'ReceiptPayload(v$version, ${type.code}, $ref)';
}

/// True if [raw] looks like the LAN-pairing QR rather than a receipt code. A
/// receipt scanner uses this to refuse a pairing code with a clear message
/// instead of mis-resolving it (§282).
bool isPairingPayload(String raw) => raw.startsWith(kPairingPrefix);

/// Builds the canonical printed-code string. Throws [ReceiptPayloadException]
/// on an unusable reference — there is no lenient path, because silently
/// encoding a bad id would print a slip that cannot be resolved.
String encodeReceiptPayload({
  required ReceiptDocType type,
  required String ref,
}) {
  if (ref.isEmpty) {
    throw const ReceiptPayloadException('reference is empty');
  }
  if (!_refPattern.hasMatch(ref)) {
    throw const ReceiptPayloadException(
      'reference must be 1-64 chars of [A-Za-z0-9_-] (opaque id, no PII)',
    );
  }
  return ReceiptPayload(
    version: kReceiptPayloadVersion,
    type: type,
    ref: ref,
  ).encode();
}

/// Strict decoder. Returns `null` for anything that is not a well-formed,
/// current-version Library Manager receipt code: a pairing payload, an unknown
/// scheme/version, a bad field count, an unknown type, an illegal reference, or
/// embedded control characters. Never throws, never guesses, never mutates.
ReceiptPayload? decodeReceiptPayload(String raw) {
  if (raw.isEmpty || raw.startsWith(kPairingPrefix)) return null;

  // Reject any control characters outright (NFC / copy-paste smuggling).
  for (final unit in raw.runes) {
    if (unit < 0x20 || unit == 0x7f) return null;
  }

  final parts = raw.split(_sep);
  if (parts.length != 3) return null;
  if (parts[0] != kReceiptScheme) return null;

  // Version is carried by the scheme tag itself (LM1 => 1). A future LM2 must be
  // handled by a matching decoder; anything newer than we understand is refused.
  if (parts[0] != 'LM$kReceiptPayloadVersion') return null;

  final type = ReceiptDocType.fromCode(parts[1]);
  if (type == null) return null;

  final ref = parts[2];
  if (!_refPattern.hasMatch(ref)) return null;

  return ReceiptPayload(version: kReceiptPayloadVersion, type: type, ref: ref);
}

/// Robust scanner resolution: extracts a member identifier from a scanned
/// QR code or barcode string.
///
/// Handles:
///  1. Rich JSON member payloads (`{"id":"MEM-1", ...}`)
///  2. Canonical receipt slip formats (`LM1|CARD|MEM-1`)
///  3. Raw member card identifiers (`MEM-1`)
String parseScannedMemberId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final id = decoded['id'] ?? decoded['memberId'];
        if (id != null && id.toString().trim().isNotEmpty) {
          return id.toString().trim();
        }
      }
    } catch (_) {}
  }
  if (trimmed.startsWith('LM1|CARD|')) {
    final parts = trimmed.split('|');
    if (parts.length >= 3 && parts[2].trim().isNotEmpty) {
      return parts[2].trim();
    }
  }
  return trimmed;
}
