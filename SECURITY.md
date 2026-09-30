# Security Policy

**Library Manager** is an offline-first, self-hosted desktop application. It
never sends patron data, credentials or telemetry to any third party. The only
network surface is the optional LAN HTTP server that lets paired workstations
share one SQLite database. This document describes how to report a vulnerability
and which security controls are already in place.

---

## Reporting a vulnerability

If you believe you have found a security issue in this project, please
**do not open a public GitHub issue**. Instead:

1. Email **security@<your-domain-here>** (replace with the maintainer's
   address configured on the repo landing page) with:
   - A short summary of the issue.
   - Steps to reproduce — a minimal scenario is enough; a proof-of-concept
     patch is even better.
   - Your assessment of impact (which roles / data / hosts are exposed).
   - Any disclosure deadline you must respect.
2. You will receive an acknowledgement within **72 hours** and a triaged
   response within **7 days**.
3. Coordinated disclosure is preferred. Give maintainers a reasonable window
   (90 days is standard) before publishing.

Only open a public issue if you have already coordinated disclosure and the
fix has shipped.

---

## Supported versions

| Version | Supported | Notes |
| --- | --- | --- |
| `1.1.x` | ✅ | Current release. |
| `1.0.x` | ⚠️ 90 days from 1.1.0 | Receives critical security fixes only. |
| Anything older | ❌ | Please upgrade; no back-ports. |

---

## Threat model

The application is intended for a **trusted LAN** inside a single library. It
is **not** designed to be exposed to the public internet, and doing so voids
the assumptions below.

### Assets we protect

- **Patron records** — names, contact details, borrowing history.
- **Financial ledger** — fines, item valuations.
- **Catalogue** — the library's own IP.
- **Administrator credentials** — the last-admin gate is a hard invariant.

### Adversaries we assume

- A curious patron with temporary physical access to a staff workstation.
- A malicious device on the same LAN attempting to talk to the host.
- A tampered client binary attempting to elevate its own role.
- Casual credential-stuffing against the login screen.

### Adversaries we do *not* assume

- A well-resourced nation-state on the LAN segment.
- Physical access to the host machine's disk (SQLite is at rest in cleartext
  in `%LOCALAPPDATA%` — use BitLocker or an equivalent volume encryption).
- Malware already running in the user's Windows session (that is a whole-OS
  trust problem, not an application problem).

---

## In-place controls

### Authentication

- **PBKDF2-HMAC-SHA256** with a **per-credential 16-byte random salt** and
  **150 000 iterations**. Salts are drawn from `dart:math` `Random.secure()`
  and stored alongside the derived key in the credential file. Identical
  passwords across users yield distinct hashes.
- **Constant-time comparison** — the derived-key check runs a full-length
  XOR accumulator so a timing side channel cannot leak prefix match length.
- **Legacy credential migration** — pre-10.1 single-unsalted-hash files are
  transparently re-hashed with a fresh salt on next successful login.
- **Reserved-name guard** — usernames `admin`, `root`, `system`, `library`
  and any case-insensitive variant cannot be claimed by a normal account;
  the built-in administrator is the only principal allowed to hold them.
- **Last-admin guard** — you cannot demote or delete the final administrator,
  so an operator can never lock themselves out of their own install.

### Brute-force resistance

- Per-source **failure counter** with a rolling 5-minute window.
- After **5 failures** the source is locked; the response is a
  `retry_after` duration so the client can back off cleanly.
- Failures never reveal whether the username exists — the response is
  byte-identical for "no such user" and "wrong password".

### Authorisation

- Three roles — `viewer`, `staff`, `admin` — enforced **server-side on every
  mutating route**. The UI hiding a button is a courtesy; a client that
  forges its way in still gets a `403`.
- Every token minted after the 10.1 upgrade is bound to a **named principal
  + role** recorded in `_principals`. Only pre-upgrade shared / pairing
  tokens retain admin, so upgrading never strands an existing client.

### Network

- HTTP server binds to `0.0.0.0` on the LAN port and **relies on the OS
  firewall**; a Windows Firewall rule scoped to **LocalSubnet** is created
  on first enable (elevation asked once, result cached).
- Every mutating HTTP request carries an **`Idempotency-Key`** so a Wi-Fi
  drop between send and ack cannot double-issue a loan or double-charge a
  fine. Keys live in a bounded in-memory LRU.
- No UPnP, no port forwarding, no cloud relay, no IPv6 link-local exposure
  beyond what the OS permits.

### Data at rest

- SQLite file lives under `%LOCALAPPDATA%\library_manager\library.db`. Not
  encrypted at application level. **For public-facing or shared machines
  enable BitLocker (or equivalent) on the volume.**
- The credential file storing PBKDF2 hashes is written with
  `FileMode.writeOnly`, so any pre-existing version is destroyed. It is
  never logged, never included in the diagnostics bundle.
- **Online backup** uses SQLite's `VACUUM INTO`, which produces a
  transactionally consistent snapshot without stopping the writer.
- **Restore** runs in a defensive transaction with a rollback journal, so a
  corrupt backup file cannot leave the live database half-applied.

### Diagnostics bundle

- Contains app version, host / client role, feature-flag snapshot, OS build,
  last N log lines with **usernames, emails and item codes redacted**.
- Never contains: password hashes, salts, session tokens, IP addresses of
  paired clients, patron names, patron addresses, fine ledger rows.

### Logging

- `AppLogger` writes a rolling log under `%LOCALAPPDATA%\library_manager\logs`.
- A hard rule enforced in review: **no secret, token, salt or PII is ever
  logged**. Any code path tempted to log one of these must be redacted at
  the sink, not at the caller, so future code cannot accidentally bypass it.

---

## Vulnerability class coverage

The following classes are covered by tests. When you add a fix, add a test to
the corresponding file so it stays fixed forever.

| Class | Where it is tested |
| --- | --- |
| Password-hash format drift | `test/services/password_hasher_test.dart` |
| Brute-force throttle | `test/services/auth_service_test.dart` |
| Last-admin guard | `test/services/auth_service_test.dart` |
| Role guard on HTTP route | `test/services/http_server_test.dart` |
| Idempotency-key replay | `test/services/idempotency_store_test.dart` |
| Optimistic-concurrency CAS | `test/services/database_service_test.dart` |
| Client cannot elevate role | `test/providers/library_provider_test.dart` |
| Backup / restore integrity | `test/services/database_service_test.dart` |

---

## Cryptographic choices — rationale

- **PBKDF2-HMAC-SHA256 (150 k iterations)** rather than bcrypt / scrypt /
  argon2 because it is implementable with `dart:convert` + `crypto` on
  pub.dev without any native dependency, which keeps the Windows bundle
  small and reproducible. If you need NIST-800-63B parity for a regulated
  deployment, run the app on a volume with BitLocker XTS-AES-256 so the
  stored hashes are protected at rest regardless of the KDF strength.
- **Random salt per credential, 16 bytes** — matches NIST SP 800-132
  recommendation.
- **Constant-time comparison** — prevents timing oracles at the derived-key
  check.
- **No TLS** on the LAN server because a private subnet inside a library is
  the deployment model, and adding TLS would require either bundling a
  CA (bad trust story) or shipping a per-install self-signed cert (users
  get unsafe-everywhere warnings). If you need TLS, put the host behind
  a reverse proxy that terminates TLS and forwards to `localhost:8931`.

---

## Contact

Replace `security@<your-domain-here>` above with your reporting address and
optionally add a PGP fingerprint here before publishing this file. If you
prefer GitHub's built-in *Report a vulnerability* private-disclosure flow,
enable it in **Settings → Security → Code security and analysis** and this
section can point at that instead.
