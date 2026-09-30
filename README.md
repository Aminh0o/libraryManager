<p align="center">
  <strong>Library Manager</strong><br/>
  <sub>A professional Windows desktop library management system.</sub>
</p>

<h1 align="center">Library Manager</h1>

<p align="center">
  A professional Windows desktop library management system —<br/>
  LAN multi-device circulation, per-copy inventory, hold queues,<br/>
  role-based access, offline-first SQLite, and full EN / FR / AR localisation.
</p>

<p align="center">
  <a href="#-download-and-install"><img alt="Download" src="https://img.shields.io/badge/download-windows%20x64-2f6feb?style=flat-square&logo=windows&logoColor=white"/></a>
  <a href="https://github.com/Aminh0o/library_manager/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Aminh0o/library_manager/ci.yml?style=flat-square&label=tests"/></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-4b2e83?style=flat-square"/></a>
  <a href="#-feature-tour"><img alt="Screens" src="https://img.shields.io/badge/screens-14-0d8a6a?style=flat-square"/></a>
  <a href="SECURITY.md"><img alt="Security" src="https://img.shields.io/badge/security-PBKDF2--HMAC--SHA256-b6236a?style=flat-square"/></a>
</p>

---

**Library Manager** is a complete, self-contained circulation system for small
and medium libraries. It runs as a single `.exe` on any Windows 10 / 11 machine,
needs no server, no Docker, no cloud account, and stores every record in a
local SQLite database that you can back up with one click. Turn on LAN sharing
and the same machine becomes the host for an arbitrary number of staff
workstations on the same network — pair by QR code in under thirty seconds.

The project is deliberately engineered as a **thin UI over an authoritative
core**: every mutation is validated, transactional and version-checked on the
host, so two clients scanning the same book at the same second cannot corrupt
the record and a forged client cannot talk itself into a higher role than the
server granted it.

---

## ✨ Feature tour

| Area | What you get |
| --- | --- |
| **Catalogue** | Books, journals, media, dual-code (internal ID + barcode), dynamic abbreviations, per-copy inventory with individual condition notes, cover images, batch import from XLSX / CSV. |
| **Circulation** | USB-HID barcode check-out / check-in, camera scanning, date-based auto-return, overdue detection, fine engine, force-return with audit trail, renewal with configurable cap. |
| **Members** | Auto-generated `YY0001` professional IDs, membership tiers, per-member loan and hold history, contact directory, GDPR-friendly right-to-erase. |
| **Reservations** | First-in / first-out hold queue with admin-driven priority reorder, per-copy holds, availability notifications, cancellation with reason codes. |
| **Reports** | Twelve read-only analytical surfaces (loans by period, overdue, member activity, inventory valuation, fine ledger, hold turn-around, etc.), one-click CSV and PDF export, deterministic rendering shared with the on-screen table. |
| **Multi-device LAN** | Turn any install into a **host** or connect a laptop as a **client**; pairing via QR or manual IP; per-device role binding; idempotency-key middleware so a flaky Wi-Fi never double-checks-out. |
| **Users & roles** | Three-tier model — **admin / staff / viewer** — enforced identically on the host SQLite path and the HTTP surface, last-admin guard, reserved-name guard, PBKDF2-HMAC-SHA256 password hashing with a per-user salt. |
| **Chat** | Peer-to-peer staff message channel on the LAN, delivered via the same authenticated token; supports text and file attachment with size cap. |
| **Localisation** | Fully localised in **English**, **Français** and **العربية**, including proper RTL layout for Arabic across every screen and every dialog. |
| **Diagnostics** | Structured rolling app log, one-click diagnostics bundle (redacted), safe-mode repair, `VACUUM INTO` online backup with verification, restore with rollback. |
| **Appearance** | Light / dark / system theme, accent colour, density, font scale — persisted per device, no rebuild required. |
| **Accessibility** | High-contrast status palette with icon + label + colour (never colour alone), screen-reader labels on every icon-only control, keyboard-navigable tables, focus indicators on all interactive widgets. |

---

## 🖼️ Screenshots

> Screenshots are bundled with each release page on GitHub. Grab the
> `screenshots.zip` asset attached to the latest tag to see every screen
> in English, French and Arabic, light and dark theme.

---

## 📥 Download and install

### Option A — Grab the prebuilt Windows binary

1. Open the [**Releases**](../../releases) page.
2. Download `LibraryManager-<version>-windows-x64.zip`.
3. Unzip to any folder (no installer, no admin rights needed).
4. Run `library_manager.exe`.

The first launch walks you through a **60-second onboarding** that lets you
choose a language, seed the local database and (optionally) declare this
machine as the LAN host.

### Option B — Build from source

```powershell
git clone https://github.com/Aminh0o/libraryManager.git
cd library_manager

flutter --version          # require Flutter 3.32+ / Dart 3.10+
flutter pub get
flutter gen-l10n           # regenerates lib/l10n/app_localizations*.dart
flutter analyze            # must be zero-issues
flutter test               # 755+ tests, ~4 min
flutter build windows --release
```

The redistributable bundle lands at
`build\windows\x64\runner\Release\` — copy the whole folder to your
target machine (the `.exe` is not standalone; it needs the sibling
`data\` and DLLs).

### Prerequisites for a source build

| Tool | Version | Notes |
| --- | --- | --- |
| Flutter SDK | `3.32.0+` | stable channel |
| Dart SDK | `3.10.1+` | ships with Flutter |
| Visual Studio 2022 | Community or higher | workload: **Desktop development with C++** |
| Windows SDK | 10.0.22621+ | installed by the VS workload |
| Git | any | for clone + LFS if you fork screenshots |

---

## 🚀 Using it

### Standalone (single machine)

Just launch the app and start adding items. Everything runs against a local
SQLite file at `%LOCALAPPDATA%\library_manager\library.db`. Backups land next
to it. No network exposure.

### Host + clients on a LAN

1. On the machine that will hold the data: **Settings → Network → Enable
   host mode**. The app opens a listening socket on port `8931` and shows a
   pairing QR code.
2. On each client: **Settings → Network → Pair with host**, scan the QR (or
   type `http://<host-ip>:8931`), pick a role for that workstation.
3. The firewall rule for the port is created on first enable; the app asks
   for elevation exactly once and stores the outcome so future launches are
   silent.

Clients read and write through the host — there is **no shared file lock** and
no risk of two machines clobbering the same record.

### Roles

| Role | Rights |
| --- | --- |
| `viewer` | Read-only across the app. Cannot check out, cannot edit catalogue, cannot see the users screen. |
| `staff` | Full circulation, catalogue CRUD, member CRUD, fines, reports. Cannot create other accounts or change roles. |
| `admin` | Everything staff can, plus user + role management and the firewall / host settings. |

Roles are enforced **server-side** on every mutating endpoint. A tampered
client that flips the local flag still gets `403` from the host.

---

## 🧱 Architecture

```
Flutter UI (widgets, screens)
        │
        ▼
Providers (LibraryProvider, AppearanceController)
        │
        ▼
Repository seam (abstract LibraryRepository)
        │
   ┌────┴─────┐
   ▼          ▼
DatabaseService    ApiService
(SQLite/FFI)        (HTTP client)
   │                    ▲
   │                    │  HTTPS/Bearer over LAN
   ▼                    │
AuthService (PBKDF2,   shelf Router (host)
roles, CAS, last-admin) ─── Idempotency-Key middleware
                                │
                                ▼
                          Domain policies
                       (HoldPolicy, LoanPolicy,
                        OverduePolicy, FineEngine)
```

Key invariants:

- **Single source of truth.** The UI never computes a figure, filters a
  report row or re-implements a rule. Every number the operator sees is
  authored by the domain layer or the database engine — which is why an
  on-screen table and its CSV/PDF export are guaranteed to agree.
- **Optimistic concurrency.** Mutating writes carry a `_touchVersion` and
  fail cleanly on CAS conflict; the client is told to re-fetch rather than
  silently stomping on the winner.
- **Idempotent LAN writes.** Every mutating HTTP request goes through an
  `Idempotency-Key` middleware so a Wi-Fi drop between "send" and
  "confirm" cannot double-charge a fine or double-issue a loan.
- **Least-privilege by default.** Tokens minted after the 10.1 upgrade are
  bound to a named principal + role; only legacy pre-upgrade pairing tokens
  fall back to admin so no paired client gets stranded on upgrade.

---

## 🧪 Testing

- `flutter test` — 755 tests across models, domain policies, provider
  behaviour, HTTP contract, l10n parity and screen widget tests.
- Every defect fixed in this project grows a regression test that fails
  against the previous build and passes against the current one.
- A dedicated `test/l10n/` suite asserts that all three ARB catalogues have
  **the same keys, the same placeholders, and no untranslated strings**.

## 🔐 Security posture

See [`SECURITY.md`](SECURITY.md) for the reporting channel and the current
cryptographic decisions (PBKDF2-HMAC-SHA256, per-user salt, 150 000 rounds,
rate-limited login with lockout, no secret ever logged, no PII in the
diagnostics bundle).

## 🗑 Data & privacy

- The application is **fully offline-first**. No telemetry, no analytics, no
  phone-home, no update server dependency (the updater only ever contacts a
  URL you configure).
- All patron, loan and fine data lives in a single SQLite file inside the
  user's `LOCALAPPDATA`. Uninstalling and deleting that folder removes every
  trace.
- The LAN HTTP server binds to the local subnet only; nothing is
  port-forwarded and no UPnP is used.

## 📖 Documentation

| Document | Purpose |
| --- | --- |
| [`README.md`](README.md) | You are here. Product overview, install, quick tour. |
| [`CHANGELOG.md`](CHANGELOG.md) | Release-by-release notes with migration guidance. |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Dev environment, code style, commit format, PR checklist. |
| [`SECURITY.md`](SECURITY.md) | Vulnerability reporting, threat model, cryptographic choices. |
| [`help_center_screen.dart`](lib/screens/help_center_screen.dart) | In-app help with searchable topic catalogue. |

## 🗺 Roadmap

The next milestones are tracked as [milestones](../../milestones) on GitHub.
Highlights currently planned:

- **v1.2** — CSV / MARC21 catalogue import; per-item shelf-list printing.
- **v1.3** — Multi-branch libraries (one host, many branches, cross-branch
  transit).
- **v1.4** — SIP2 / NCIP bridge so existing self-checkouts can talk to the
  host.
- **v2.0** — Cross-platform shells (Linux / macOS) once the Windows product
  reaches feature-parity with commercial ILS tools at this tier.

## 🤝 Contributing

Bug reports, feature requests and pull requests are welcome — please read
[`CONTRIBUTING.md`](CONTRIBUTING.md) first. The short version:

- One logical change per PR.
- Add or extend tests. `flutter analyze` and `flutter test` must be clean
  before CI will accept your branch.
- Use the [Conventional Commits](https://www.conventionalcommits.org/)
  format (`feat:`, `fix:`, `perf:`, `docs:`, `refactor:`, `test:`, `chore:`).

## 🙏 Acknowledgements

Built with [Flutter](https://flutter.dev), [Material 3](https://m3.material.io),
[sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi),
[shelf](https://pub.dev/packages/shelf),
[data_table_2](https://pub.dev/packages/data_table_2),
[dart_pdf](https://pub.dev/packages/pdf) and
[google_fonts](https://pub.dev/packages/google_fonts).

## 📜 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.
