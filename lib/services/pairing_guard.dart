/// Per-source brute-force throttle for LAN pairing (NET-02).
///
/// The pairing responder used to evaluate every `LIB_PAIR_REQ` an unlimited
/// number of times, so a persistent attacker on the LAN could grind through
/// the ~1e6 six-digit code space over the 5-minute lifetime of an active
/// code. This guard caps how many *wrong* attempts a single source address
/// may make before it is locked out for [lockoutWindow]; a correct attempt
/// clears the source's counter so a legitimate client pairing normally is
/// never penalised by an earlier typo.
///
/// Deliberately framework-free and clock-injectable (mirrors [AuthService]'s
/// login throttle) so it is fully unit-testable without any UDP socket. It is
/// only the *attempt-counter* half of NET-02: the plaintext-code eavesdropper
/// / response-authentication half is left open (see the audit register).
class PairingGuard {
  PairingGuard({
    this.maxFailedAttempts = 6,
    this.lockoutWindow = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Wrong attempts tolerated from one source before it is locked out.
  final int maxFailedAttempts;

  /// How long a source stays locked out, and the sliding window over which
  /// failures are counted.
  final Duration lockoutWindow;

  final DateTime Function() _now;
  final Map<String, _PairingAttempts> _bySource = {};

  /// Whether a pairing REQ arriving from [sourceIp] should be evaluated at all.
  /// `false` means the source is currently locked out — the caller must
  /// silently drop the datagram (no signal back to a would-be attacker). A
  /// source that has never failed is not tracked and is always allowed.
  bool allowAttempt(String sourceIp) {
    final now = _now();
    final entry = _bySource[sourceIp];
    if (entry == null) return true;
    return !entry.isLocked(now, lockoutWindow);
  }

  /// Records a failed pairing attempt (wrong / expired code) from [sourceIp],
  /// engaging a lockout once [maxFailedAttempts] is crossed.
  void recordFailure(String sourceIp) {
    final now = _now();
    final entry = _bySource.putIfAbsent(sourceIp, _PairingAttempts.new);
    entry.recordFailure(
      now,
      maxAttempts: maxFailedAttempts,
      window: lockoutWindow,
    );
  }

  /// Clears [sourceIp]'s failure history after a successful pairing.
  void recordSuccess(String sourceIp) => _bySource.remove(sourceIp);

  /// Number of sources currently tracked (test / observability aid).
  int get trackedSources => _bySource.length;

  void clear() => _bySource.clear();
}

class _PairingAttempts {
  int _failures = 0;
  DateTime? _lastFailure;
  DateTime? _lockedUntil;

  /// Increments the failure count; returns true iff this failure engaged a
  /// lockout (until `now + window`).
  bool recordFailure(
    DateTime now, {
    required int maxAttempts,
    required Duration window,
  }) {
    _failures++;
    _lastFailure = now;
    if (_failures >= maxAttempts) {
      _lockedUntil = now.add(window);
      return true;
    }
    return false;
  }

  void _reset() {
    _failures = 0;
    _lastFailure = null;
    _lockedUntil = null;
  }

  bool isLocked(DateTime now, Duration window) {
    if (_lockedUntil != null) {
      if (now.isBefore(_lockedUntil!)) return true;
      _reset(); // lockout has elapsed
    }
    if (_lastFailure != null && now.difference(_lastFailure!) >= window) {
      _reset(); // activity window elapsed with no new failure
    }
    return false;
  }
}
