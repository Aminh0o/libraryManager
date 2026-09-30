import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import 'api_service.dart' show ApiException;
import 'database_service.dart'
    show
        ActiveLoanConflictException,
        AttributeConflictException,
        BarcodeConflictException,
        ConcurrentUpdateConflictException,
        CopyConflictException,
        InvalidStatusException,
        ItemCodeConflictException,
        MemberIdConflictException;

/// ARC-07: a capability that exists only on the host machine (backup, restore,
/// full wipe, bulk import). Thrown by the provider in place of a hard-coded
/// French sentence, so the operator reads it in their own session language --
/// and a caller can still recognise the refusal by TYPE rather than matching a
/// translated string. Extends [StateError] so any existing generic handler keeps
/// working unchanged.
class HostOnlyFeatureException extends StateError {
  HostOnlyFeatureException(String feature) : super('$feature is host-only');
}

/// FE2-12: turn any thrown error into a SHORT, LOCALIZED, CATEGORIZED message
/// instead of leaking the raw `'Erreur: $e'` — which dumped exception class
/// names, English server strings and internal detail straight to the operator.
/// The raw error is still logged via [debugPrint] so it stays diagnosable.
///
/// Two error shapes reach the UI and are both handled here:
///  * a LAN client sees [ApiException], whose `statusCode` is exactly what the
///    embedded server assigned (the server maps every host conflict / bad
///    request / auth failure to the right 4xx/5xx — see the BE-02 error
///    middleware), so status is the authoritative category; and
///  * the HOST talks to [DatabaseService] directly and gets the typed conflict
///    exceptions below, which never pass through HTTP.
String describeError(AppLocalizations l10n, Object e) {
  if (e is ApiException) {
    switch (e.statusCode) {
      case 401:
      case 403:
        return l10n.errAuth;
      case 404:
        return l10n.errNotFound;
      case 409:
        return l10n.errConflict;
      case 400:
        return l10n.errBadRequest;
      default:
        if (e.statusCode >= 500) return l10n.errServerError;
        return l10n.errGeneric;
    }
  }

  // Transport-level failures: the server is down, unreachable, or slow.
  if (e is SocketException) return l10n.errNetwork;
  if (e is http.ClientException) return l10n.errNetwork;
  if (e is TimeoutException) return l10n.errNetwork;

  // Host-side (direct DB) integrity conflicts, categorized without leaking the
  // concrete type name to the operator.
  if (e is ActiveLoanConflictException ||
      e is ConcurrentUpdateConflictException ||
      e is ItemCodeConflictException ||
      e is BarcodeConflictException ||
      e is MemberIdConflictException ||
      e is AttributeConflictException ||
      e is CopyConflictException) {
    return l10n.errConflict;
  }

  // BL-05: a title status outside the copy-derived vocabulary is an invalid
  // input VALUE. The server maps it to HTTP 400 (handled by the ApiException
  // branch above); the host gets it straight from DatabaseService, so map it to
  // the same localized bad-request message rather than the generic fallback.
  if (e is InvalidStatusException) return l10n.errBadRequest;

  // ARC-07: a host-only capability was asked for on a client. This is not a
  // malfunction, so it must not read as "something went wrong" -- the operator
  // needs to know WHERE to go instead.
  if (e is HostOnlyFeatureException) return l10n.errHostOnlyFeature;

  // Unknown: never surface the raw object. Log it and show a generic message.
  debugPrint('describeError uncategorised: $e');
  return l10n.errGeneric;
}
