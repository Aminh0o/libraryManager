<h1 align="center">📚 Library Manager</h1>

<p align="center">
  A professional Windows desktop library management system —<br/>
  LAN multi-device circulation, per-copy inventory, hold queues,<br/>
  role-based access, offline-first SQLite, and full EN / FR / AR localisation.
</p>

<p align="center">
  <a href="#-download-and-install"><img alt="Download" src="https://img.shields.io/badge/download-windows%20x64-2f6feb?style=flat-square&logo=windows&logoColor=white"/></a>
  <a href="https://github.com/Aminh0o/libraryManager/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Aminh0o/libraryManager/ci.yml?style=flat-square&label=tests"/></a>
  <a href="https://github.com/Aminh0o/libraryManager/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Aminh0o/libraryManager?style=flat-square&color=0d8a6a&label=release"/></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-4b2e83?style=flat-square"/></a>
  <a href="#-feature-tour"><img alt="Screens" src="https://img.shields.io/badge/screens-23-0d8a6a?style=flat-square"/></a>
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
| **Catalogue** | Books, journals, media, dual-code (internal ID + barcode), dynamic abbreviations, per-copy inventory with individual condition notes, cover images, bibliographic detail (author, publisher, year, language, description), batch import from XLSX / CSV. |
| **Cataloguing speed** | Type or scan an ISBN and the item fills itself in from Open Library / Google Books — title, author, publisher, year, subject, blurb and cover. HTTPS only, five seconds per provider, and the form stays editable, so a machine with no internet loss nothing. |
| **Circulation** | USB-HID barcode check-out / check-in (keyboard-wedge scanners; typed codes work too), date-based auto-return, overdue detection, fine engine, force-return with audit trail, renewal with configurable cap, selectable loan period at the desk. |
| **Self-service & shelf work** | A locked-down **kiosk** screen patrons can use to borrow and return by themselves, a **stocktake** mode that scans the shelves and reports missing or misplaced copies, and printable **A4 barcode label sheets** with vector Code 128. |
| **Members** | Auto-generated `YY0001` professional IDs, membership tiers, card photo, status and expiry, per-member loan and hold history, contact directory, GDPR-friendly right-to-erase. |
| **Reservations** | First-in / first-out hold queue with admin-driven priority reorder, per-copy holds, availability notifications, cancellation with reason codes. |
| **Reports & analytics** | Twelve read-only analytical surfaces plus a live **analytics** screen (demographics, loan velocity, overdue rate, collection distribution, fine recovery), one-click CSV and PDF export, deterministic rendering shared with the on-screen table. |
| **Multi-device LAN** | Turn any install into a **host** or connect a laptop as a **client**; pairing via QR or manual IP; per-device role binding; idempotency-key middleware so a flaky Wi-Fi never double-checks-out. |
| **Users & roles** | Three-tier model — **admin / staff / viewer** — enforced identically on the host SQLite path and the HTTP surface, last-admin guard, reserved-name guard, PBKDF2-HMAC-SHA256 password hashing with a per-user salt. |
| **Chat** | Peer-to-peer staff message channel on the LAN, delivered via the same authenticated token; ephemeral text messages with a 1,000-character cap and rolling buffer. |
| **Localisation** | Fully localised in **English**, **Français** and **العربية**, including proper RTL layout for Arabic across every screen and every dialog. |
| **Diagnostics** | Structured rolling app log, one-click diagnostics bundle (redacted), safe-mode repair, `VACUUM INTO` online backup with verification, restore with rollback. |
| **Appearance** | Light / dark / system theme, accent colour, density, font scale, custom library name and logo — persisted per device, no rebuild required. Re-branding also rewrites the Windows desktop and Start Menu shortcuts. |
| **Updates** | The app checks GitHub on startup (administrator only, at most once every twelve hours) and offers a verified in-app download of the new package, with a SHA-256 check before it installs anything. |
| **Accessibility** | High-contrast status palette with icon + label + colour (never colour alone), screen-reader labels on every icon-only control, keyboard-navigable tables, focus indicators on all interactive widgets. |

---

## 🖼️ Seeing it

There is no screenshot gallery in this repository: the product holds real
patron records and the demo data is not separable enough to publish safely.
Instead, every release ships the real thing — install it and the first launch
gives you a 60-second onboarding, the dashboard carries a **guided spotlight
tour** of each surface, and the Help Center holds a written walkthrough of every
screen in English, French and Arabic. If you want a guided look before
installing, open an issue and we will walk you through a hosted session.

---

## 📥 Download and install

### Option A — Run the installer (recommended)

1. Open the [**Releases**](../../releases/latest) page.
2. Download `LibraryManager-Setup-<version>-windows-x64.exe`.
3. Run it. Install for **your user only** (no admin rights) or for every user on
   the machine when prompted; choose a Start Menu shortcut and, optionally, a
   desktop icon.
4. Launch *Library Manager*.

The Setup package contains the Visual C++ runtime files it needs, so it starts
on a clean Windows 10 / 11 machine with nothing else installed — no redistributable
to find and install first.

To uninstall: *Apps & Features* → Library Manager → Uninstall, or run
`unins000.exe` in the install folder (`/VERYSILENT` works for imaging).

The first launch walks you through a **60-second onboarding** that lets you
choose a language, seed the local database and (optionally) declare this
machine as the LAN host.

### Option B — Use the portable bundle

Download `LibraryManager-<version>-windows-x64.zip`, extract it **whole** to any
folder and run `library_manager.exe` from there. The `.exe` is not standalone —
it needs the `data\` folder and the DLLs that sit beside it, so keep the folder
structure intact. This is the bundle the in-app updater offers, and it needs no
admin rights.

Every release attaches a `<file>.sha256sum` next to each download so you can
verify what you got:

```powershell
Get-FileHash .\LibraryManager-Setup-<version>-windows-x64.exe -Algorithm SHA256
# compare (case-insensitively) with the digest inside the .sha256sum file
```

### Option C — Build from source

```powershell
git clone https://github.com/Aminh0o/libraryManager.git
cd libraryManager

flutter --version          # require Flutter 3.32+ / Dart 3.10+
flutter pub get
flutter gen-l10n           # regenerates lib/l10n/app_localizations*.dart
flutter analyze            # must be zero-issues
flutter test               # 930+ tests, ~4 min
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
SQLite file at `%USERPROFILE%\Documents\library_manager.db`, with automatic
backups in `Documents\library_backups\`. No network exposure.

### Host + clients on a LAN

1. On the machine that will hold the data: **Settings → LAN → Host**. The app
   binds the HTTP API on TCP `8080` and the pairing-discovery socket on UDP
   `19001`, then shows a pairing QR code.
2. On each client: **Settings → LAN → Client**, scan the QR (or enter the
   pairing code, or type the host address `http://<host-ip>:8080`), then pick a
   role for that workstation.
3. On the first host start the app offers to open the Windows Firewall for
   those two ports — a single UAC prompt whose outcome is remembered, so later
   launches are silent. If a client still cannot find the host, **Settings →
   Data Protection → Pairing diagnostic** reports exactly which prerequisite
   (port listening, firewall rule, or a blocking rule) is missing.

Clients read and write through the host over Bearer-authenticated HTTP — there
is **no shared file lock** and no risk of two machines clobbering the same
record.

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
   │                    │  HTTP + Bearer over LAN
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

- The application is **offline-first**. No telemetry, no analytics, no
  phone-home. There are exactly three kinds of outbound request in the whole
  product, and each one is deliberate, tiny and listed here:
  1. **ISBN lookup** sends the ISBN you typed or scanned to Open Library, then
     Google Books, to fill in the catalogue form. It runs when the operator
     presses the lookup button, and once more automatically when a scanned
     barcode is not yet in the catalogue and looks like an ISBN (10+ digits).
     It carries no patron, loan or fine data — only the ISBN. Both calls are
     HTTPS with a five-second timeout.
  2. **Update check** asks GitHub for the newest release tag (an administrator
     session only, at most once every twelve hours) so the app can tell you an
     update exists.
  3. **Download** fetches the release package from the URL that check returns
     and verifies its SHA-256 before using it.
  Everything else — the database, backups, logs, receipts, reports — never
  leaves the machine or the local subnet.
- All patron, loan and fine data lives in a single SQLite file,
  `\<user\>\Documents\library_manager.db`, with automatic backups beside it in
  `Documents\library_backups\`. Uninstalling and deleting those two folders
  removes every trace.
- The LAN HTTP server binds to the local subnet only; nothing is
  port-forwarded and no UPnP is used. Client pairing and every mutating request
  are authenticated and role-checked once any credential exists on the host.

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

- **v1.2** — done and shipped: ISBN auto-cataloguing, kiosk self-checkout,
  shelf stocktake, analytics, A4 barcode label sheets.
- **v1.3** — CSV / MARC21 catalogue import; per-item shelf-list printing;
  richer circulation lists (sorting, days-late, pagination on loans).
- **v1.4** — Multi-branch libraries (one host, many branches, cross-branch
  transit).
- **v1.5** — SIP2 / NCIP bridge so existing self-checkouts can talk to the
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
