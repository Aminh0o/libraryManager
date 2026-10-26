# Changelog

All notable changes to **Library Manager** are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.2.0] — 2026-10-26

Codename *shelves-to-suite*. The largest single release of the project: the
catalogue grows real bibliographic detail, the desk gains three new ways to work
(self-service kiosk, shelf stocktake, analytics), the paper trail becomes
printable in all three languages, and the whole product was re-verified from a
clean checkout end to end.

### Added

- **ISBN auto-cataloguing.** Typing or scanning an ISBN in the item form now
  fills title, author, publisher, year, category and description from public
  cataloging APIs (Open Library, then Google Books), with the cover fetched as
  well. HTTPS only, 5-second budget per provider, and it fails into an empty
  form rather than a wrong one — the operator can always type the details by
  hand, so cataloguing never depends on internet access.
- **Self-service kiosk mode.** A locked-down, touch-friendly, high-contrast
  screen where a patron scans their card and checks out or returns a copy
  themselves. Reaching the staff controls behind it requires the admin password,
  and every kiosk action flows through the same loan state machine as the staff
  desk, so fines, holds and history stay authoritative.
- **Shelf stocktake.** Scan the shelf and the screen reports present, missing
  and misplaced copies against what the catalogue expects, with manual barcode
  entry for damaged labels and an exportable audit record for the missing ones.
- **Advanced analytics.** A statistics screen covering membership demographics,
  loan velocity and overdue rate, collection distribution by type and fine
  recovery, computed server-side from the same queries the reports use.
- **Printable barcode label sheets (A4).** Generate a sheet of Code 128 labels
  with title, author and shelf location from the item detail screen, print it,
  and stick it on the spine. Barcodes are drawn as vectors, so they scan at any
  printer resolution.
- **Bibliographic detail on the catalogue.** Items carry author, category,
  description, language, publisher, publication year and a cover image; members
  carry a photograph, card type, status, expiry date, address and notes. Schema
  v24, additive columns with defaults, so an existing database upgrades in place
  on first launch (the v9→v24 path is covered by a migration test), and a backup
  from a *newer* schema is refused on restore rather than silently downgraded.
- **Arabic and French paperwork that actually prints.** Circulation receipts,
  loan slips and report PDFs now ship with a bundled Arabic font
  (IBM Plex Sans Arabic, OFL 1.1), so Arabic text renders as letters instead of
  empty boxes, and labels follow right-to-left order.
- **In-app update notices.** On startup an administrator gets one quiet toast
  when a newer release exists, deduplicated per version and rate-limited to one
  check per twelve hours. Nothing is shown when the check is unconfigured,
  already current or simply failed — the app never claims it is up to date when
  it could not look.
- **Re-branding follows the shortcut.** Changing the library name or logo now
  also rewrites the Windows desktop and Start Menu shortcuts, so a re-branded
  installation looks re-branded before it is even opened.
- **Spotlight tour on the dashboard.** A guided cut-through of the dashboard
  controls for a new operator, in all three locales.
- **Desktop keyboard coverage test.** A widget test asserts the documented
  shortcuts (search focus, palette, navigation) reach the right handlers on
  Windows rather than only on a phone-sized layout.

### Improved

- **LAN security is now enforced, not just available.** Before this release a
  freshly-started host served reads *and writes* to anyone on the network until
  somebody happened to set a password. Enforcement now engages as soon as a
  credential exists, role checks are applied per route (a viewer cannot write,
  staff cannot manage accounts), and failed logins are throttled per source IP
  into a lockout that returns `429` with a retry window. Verified live against
  the running server, not only in unit tests.
- **Bare-PC installation.** The build pipeline now deploys the Visual C++
  runtime app-local before packaging. Previously the Setup package only started
  on machines that already had the VC++ 2015–2022 redistributable — which the
  counter PC in a library almost never has — and Windows refused to launch the
  exe at all. A guard test keeps `pubspec.yaml`, the in-app version string, the
  installer script and the installer builder on one version number.
- **Search, filters and pagination are server-side on every list** that grew
  past a page, with the clear-search affordance and camera/scanner button
  coexisting in the field, and offline states rendered as a real error plus
  retry instead of an empty list pretending the catalogue is empty.
- **Copy quality in French and Arabic.** Localization parity is now asserted
  test-side per key and per placeholder; the French plural/truncation defects and
  the Arabic right-to-left issues found in the verification pass were fixed at
  the source ARB files rather than patched in widgets.

### Fixed

- Pagination flags defaulted to optimistic `true`, which showed a spinner
  forever at the end of a short list; they now start false and are set from the
  server response.
- The inventory list's offline branch rendered a blank panel; it renders the
  network error state with a retry button.
- Several right-to-left layouts placed chevrons, avatars and mixed
  number-plus-unit strings ("99+", "Retard de 3 jours") on the wrong side or with
  broken bidi ordering.

### Verified for this release

- `flutter gen-l10n`, `dart format --set-exit-if-changed lib test`,
  `flutter analyze --no-pub` and `flutter build windows --release` all clean.
- Full suite: 930 tests passing, 1 skipped (schema migrations, LAN routes, auth
  roles, rate limiting, idempotency, receipt payloads, widget states).
- Manual pass on the real Windows build across the inventory, circulation,
  settings, security, pairing and LAN surfaces in English, French and Arabic,
  plus live API probes against a running host from a second process (unauthenticated
  read/write behaviour, token login, the admin/staff/viewer role matrix and the
  brute-force lockout).
- **Not yet manually verified:** the three surfaces added in this release — kiosk,
  stocktake and analytics — have automated test coverage of their logic and states,
  but they have not been driven through the real window in all three locales the way
  the rest of the product has. Treat them as the least-proven part of 1.2.0.

### Known issues (deliberately shipped, tracked)

- The three new surfaces (kiosk, stocktake, analytics) carry automated coverage
  but not yet a manual pass in all three locales — see *Verified for this release*.
- The circulation lists are still thin on large catalogues: no per-column sort
  on loans, no days-late column on the fine list, and the item detail panel
  hides metadata below the fold at narrow window widths.
- Command palette navigation works, but searching the palette for an item or a
  member by name is not implemented yet.
- Barcode *camera* scanning is a mobile feature; on Windows the scanner dialog
  correctly expects a USB (keyboard-wedge) scanner or typed code, so a webcam
  scan on desktop is not available.
- Copy vocabulary for a few circulation statuses is stored as French literals in
  the seeded code definitions; those labels render in French even in the English
  UI until they move behind the localization layer.

---

## [1.1.5] — 2026-10-17

Codename *white-label-and-teach*. Closes the last "high-end product" gaps an
operator hits before a real deployment: the product now teaches itself in all
three languages, carries a customer's own brand, gives the circulation desk a
say in loan length, and reports every action with clear, semantic feedback.

### Added

- **Native Windows installer (Inno Setup).** A professional `Setup.exe` with an
  EN/FR/AR wizard, per-user or elevated install, Start Menu shortcut, optional
  desktop icon, and full silent install/uninstall support
  (`/VERYSILENT`). Built and Authenticode-signed by
  `scripts/build_installer.ps1`; the installer carries the same signed binary
  as the portable zip and installs into the standard Programs folder with a
  registered entry in *Apps & Features*.
- **Custom app logo (white-label).** Alongside the existing brand-name and
  accent-color controls, an administrator can now upload the library's own logo
  (PNG/JPG). The image is size-bounded, copied into the app's private branding
  folder so it survives the original being moved or deleted, shown in the
  navigation header, and removable with one click. A missing or unreadable file
  falls back to the built-in glyph — the header can never blank out.
- **Selectable loan period at checkout.** The circulation desk can now choose a
  7/15/30-day period when issuing a loan instead of a fixed 15-day default;
  the due date is derived from that choice through the canonical loan state
  machine, so fines, renewal and overdue tracking all follow it. Defaults to the
  historical value, so nothing changes until the operator picks otherwise.

### Improved

- **The tutorial map and hardware guide are now localized.** They previously
  rendered in English only, so French and Arabic operators opened the one screen
  meant to *teach* them the product and got a language they might not read. All
  nine tutorial steps, both card headers and the full hardware-desk guide now
  ship in English, French and Arabic, and follow right-to-left layout.
- **Semantic feedback everywhere.** A single toast surface now carries a
  success / error / warning / information icon and colour, so a completed action
  and a refused one are unmistakable at a glance in any language. Adopted across
  the loan desk (checkout, return, renewal), settings saves and logo changes.

---

## [1.1.4] — 2026-10-16

Codename *download-and-verify*. Turns the update check into a real updater and
puts the circulation paperwork in the operator's hands.

### Added

- **In-app download with checksum verification.** The updater no longer just
  opens a browser page: it now streams the GitHub release package
  (`LibraryManager-<ver>-windows-x64.zip`) into the user's Documents, verifies
  its SHA-256 against the release's published `.sha256sum` sibling, and only
  then hands the verified file over with clear manual-install steps. The feed is
  HTTPS-only, a size cap bounds the download, the download is cancel- and
  resume-safe, and the destination directory is created on demand. When no
  checksum asset is published, the download is refused rather than offered
  unverifiable. The app never auto-extracts, replaces the running executable, or
  elevates — installing stays a deliberate, user-visible act.
- **Printable circulation receipts in the UI.** Return/renewal receipts, hold
  tickets and the member card are now reachable from their own screens (loan,
  reservations, member detail), gated to writable sessions, and write a real PDF
  to a location the operator chooses. Receipts carry the circulation facts, not
  PII, and use the strict receipt payload codec.

### Verified

- LAN pairing/sharing re-confirmed end to end: role-gated single-use pairing
  code, real bound-port advertisement, broadcast plus subnet-scan discovery,
  per-source wrong-code lockout, bearer token (no password on the wire), the
  `LanServerErrorKind` reachability taxonomy and the in-app pairing self-diagnostic
  / firewall helper.

---

## [1.1.3] — 2026-10-02

Codename *named-account sign-in*. Closes the field report that a staff account
created on the host could not sign in from a client PC: the client showed
"Sign-in failed. Check the username and password." — which reads as "does not
exist" — even when the credentials were correct.

### Fixed

- **Case-insensitive named-account login.** Accounts are stored normalized
  (lowercase) by `addUser`, but `AuthService.login`, `verifyUserPassword`,
  `removeUser`, `changeUserRole` and `setUserPassword` matched the username
  **case-sensitively** against that store. A host-created account for "Fatima"
  (stored as `fatima`) therefore could never be signed into by typing "Fatima",
  and the same account looked "missing" to role and password administration.
  Every identity lookup now normalizes through `UserRecord.normalizeUsername`,
  so host-created staff accounts sign in from any client regardless of the case
  typed. Credential verification is unchanged — a wrong password is still
  refused — and the SEC-03 contract (never reveal whether an account exists)
  is preserved.

- **Client sign-in box.** The client sign-in dialog normalizes the typed
  username before calling the host, so the retry and error path behave
  identically whatever case the operator enters.

### Tests

- Added regression coverage for mixed-case sign-in and mixed-case admin
  operations in `test/services/auth_service_roles_test.dart`.

---

## [1.1.2] — 2026-09-30

Codename *pairing reliability*. Closes the field report that a client could not
discover the host over LAN. The root cause is almost always that Windows
Firewall on the host never opened UDP 19001 — the rule used to sit behind a
manual Settings button that a first-time host had no reason to click. This
release makes the prerequisite self-announcing and self-diagnosing.

### Added

- **One-time firewall prompt on first host start.** When a machine is in Host
  mode on Windows and the LAN rules have never been offered, `HomeScreen` now
  shows a single explanatory dialog (deferred to a post-frame callback) asking
  to open UDP 19001 (pairing discovery) and TCP 8080 (HTTP API). Accepting runs
  the existing elevated `WindowsFirewallService.ensureLanFirewallRules()`;
  declining is remembered. The choice is persisted via a `firewall_prompt_shown`
  flag so it never nags again.

- **Pairing diagnostic tool** in Settings → Data Protection. A non-elevated
  `WindowsFirewallService.runPairingDiagnostic()` runs read-only PowerShell
  checks and returns a structured result rendered as a checklist: whether UDP
  19001 is actually listening, whether the Library Manager firewall rules are
  installed and enabled, and whether an inbound Block rule (commonly added by
  antivirus network filters) is intercepting the port. Requires no admin rights.

### Changed

- **Richer "host not found" guidance.** The client-side pairing failure message
  is now a detailed six-point checklist (`pairingHostNotFoundDetailed`) covering
  firewall, host-mode, code expiry, AP isolation, cross-subnet broadcast, and
  antivirus filtering — shown for 12 seconds instead of a fleeting snackbar.

- **Localisation.** All new strings shipped in EN / FR / AR.

---

## [1.1.1] — 2026-09-30

Codename *post-release hardening*. Two follow-ups on top of 1.1.0 that close
the last two "not quite 10/10" items in the production-readiness audit, plus a
format baseline that keeps CI green for every future contributor.

### Fixed

- **Circulation - French error sentences leaking into the audit trail**.
  Two provider-level refusals (`item not available`, `no active loan for
  scan`) were thrown as raw `Exception('Cet article ...')` / `Exception('Aucun
  emprunt ...')` strings. On an English or Arabic session the operator saw the
  French sentence because `describeError` fell through to the generic
  fallback, and the same sentence ended up in `debugPrint`. They now throw
  typed `ItemNotAvailableException` / `NoActiveLoanException` values that
  `describeError` maps to the existing `l10n.itemNotAvailable` and
  `l10n.noActiveLoan` strings, so every locale reads correctly.

### Added

- **Global error boundary** in `lib/main.dart`. `FlutterError.onError` and
  `runZonedGuarded` are now installed at startup so a widget build failure, a
  listener that throws during `notifyListeners`, or any uncaught async error
  is captured to the rotating diagnostic log (`appLog.error('flutter', ...)`
  and `appLog.error('unzone', ...)`) rather than appearing as an unreadable
  red box or a silent crash. Errors that arrive before the logger is wired
  are buffered in memory and flushed once `initAppLogging` completes.

### Changed

- **`dart format` baseline**. The CI workflow that shipped in 1.1.0 gates on
  `dart format --set-exit-if-changed`. The codebase had never been run through
  the formatter with those gates in place, so every PR failed with a wall of
  "Changed <file>" lines. A one-shot `dart format .` reflowed 150 files with
  zero semantic change; four pre-existing
  `curly_braces_in_flow_control_structures` infos surfaced afterwards and were
  fixed in the same pass.

### Migration notes

No schema change. Clients on 1.1.0 continue to interoperate; the LAN wire
protocol is identical. Upgrading from 1.1.0 to 1.1.1 is a straight swap of
the bundle.

---

## [1.1.0] — 2026-09-30

Codename *production-hardened*. This release closes every defect uncovered
by the internal pre-release audit, tightens the LAN protocol and standardises
the operator-facing copy so the product is safe to distribute.

### Fixed

- **Circulation - Confirm Return** no longer silently no-ops when the
  barcode field is empty. The button is disabled until a code is scanned or
  typed, so a distracted operator cannot click "return" and believe the
  transaction landed.
- **Chat - Send** is disabled while the input is empty. Same class of bug:
  an empty message was accepted into the send queue and dropped silently,
  leaving the sender with no feedback.
- **Reservations - live hold rows** now render their status chip in the
  trailing column alongside the cancel button. Previously only ended rows
  showed a chip, so operators could not distinguish *queued* from *available
  for pickup* without opening each row.
- **Members - delete** uses a dedicated "Delete Member" string in tooltip,
  dialog title and confirm button. Previously the shared item-delete string
  was reused, which read as "Delete Item" on a member row.
- **Item-delete dialog** is fully localised. A hard-coded French sentence
  slipped through EN / AR builds and has been replaced by a parameterised
  `confirmDeleteItemNamed(item)` key.
- **Users & Roles - subtitle** no longer leaks the raw `DateTime.toString()`
  with `T` separator and microsecond tail. Timestamps render as
  `YYYY-MM-DD HH:MM`.
- **Users & Roles - empty state** is honest. The screen previously said "No
  accounts yet" while the operator was actively signed in as the built-in
  administrator. It now explains the real situation and points at the
  create-account action.
- **Users & Roles - role picker** inside the create / change dialogs is a
  `SegmentedButton` rather than a `DropdownButtonFormField`, so the menu no
  longer opens an overlay that occludes the Cancel / Create buttons.
- **Reports - Generated ...** header no longer shows the raw ISO-8601
  timestamp from the SQLite `generated_at` column. It is routed through
  `AppDate` and falls back gracefully for unparseable values.
- **NavigationRail** actually collapses. The rail's `leading` width was
  hard-coded to 236 px regardless of the `extended` flag, so the
  collapse / expand toggle visually did nothing. Leading width now tracks
  the mode (236 px extended, 72 px collapsed) and the toggle is placed at
  the top of the rail per Material 3 desktop convention.
- **HoldPolicy.queueOrder** comparator now matches the SQL
  `COALESCE(rank, id) ASC, id ASC` ordering, so client-side reorder labels
  update in lock-step with the server.

### Added

- `lib/utils/app_date.dart` — central, pure-Flutter date formatter.
  Removes per-screen `_fmtDate` drift and prevents raw `DateTime.toString()`
  from ever reaching the UI.
- `AppSizing.maxDialogWidth = 560` — the app-wide dialog width cap, applied
  to every form-heavy dialog so long dropdown labels never overflow.
- Seven new localisation keys (`deleteMember`, `confirmDeleteMember`,
  `confirmDeleteItemNamed`, `reportGeneratedOn`, `userJoinedOn`,
  `noNamedAccounts`, `noNamedAccountsHint`) shipped in **EN, FR, AR** with
  full placeholder metadata.
- GitHub repository hygiene: MIT `LICENSE`, hardened `.gitignore`,
  `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, issue & PR templates,
  CI workflow, release-on-tag workflow.

### Changed

- `pubspec.yaml` version bumped from `1.0.0+2` to `1.1.0+4`, and the
  description rewritten as the public-facing product tagline.
- `lib/config/app_info.dart` kept in step with `pubspec.yaml`.
- `IconButtonTheme` in `app_theme.dart` uses `WidgetStateProperty.resolveWith`
  for the disabled state so dimming survives the theme re-publish that
  `ListTile.trailing` performs.

### Migration notes

Nothing that a downstream user must do. The SQLite schema is unchanged from
`1.0.0`. On first launch after upgrading, the app performs the normal
defensive migration check and does nothing else. Paired LAN clients on
`1.0.0` continue to interoperate; the HTTP contract is byte-compatible.

---

## [1.0.0] — 2026-09-19

Initial production release. Feature-complete circulation, catalogue, member,
reservation, fine, report, chat, users-and-roles and settings surfaces across
English, French and Arabic.

### Added

- **Catalogue** — dual-code items (barcode + internal ID), dynamic
  abbreviations, per-copy inventory with condition notes, cover images,
  XLSX / CSV batch import.
- **Circulation** — USB-HID barcode check-out / check-in, camera scanning,
  date-based auto-return, overdue detection, fine engine, force-return with
  audit trail, renewal with configurable cap.
- **Members** — auto-generated `YY0001` IDs, membership tiers, per-member
  loan and hold history, right-to-erase.
- **Reservations** — FIFO hold queue, per-copy holds, availability
  notifications, cancellation with reason codes.
- **Reports** — twelve read-only analytical surfaces, deterministic CSV and
  PDF exports sharing the on-screen table's data source.
- **LAN multi-device** — host / client mode, QR pairing, per-device role
  binding, `Idempotency-Key` middleware, `_touchVersion` optimistic
  concurrency.
- **Users & roles** — admin / staff / viewer enforced identically on the
  SQLite host path and the HTTP surface; PBKDF2-HMAC-SHA256 with per-user
  salt and 150 000 rounds; last-admin guard; reserved-name guard.
- **Chat** — peer-to-peer staff channel on the LAN, authenticated via the
  same token as circulation.
- **Localisation** — full EN / FR / AR with RTL layout on Arabic.
- **Diagnostics** — rolling app log, one-click redacted bundle, safe-mode
  repair, `VACUUM INTO` online backup with verification, restore with
  rollback.
- **Appearance** — light / dark / system theme, accent colour, density,
  font scale, per-device persistence.
- **Accessibility** — high-contrast status palette with icon + label +
  colour (never colour alone), screen-reader labels on every icon-only
  control, keyboard-navigable tables.

---

## Unreleased

Planned for 1.2.0:

- CSV / MARC21 catalogue import.
- Per-item shelf-list printing.
- Bulk edit for location, price and abbreviation.
- Windows installer (MSIX) in addition to the portable zip.

[1.1.0]: https://github.com/Aminh0o/libraryManager/releases/tag/v1.1.0
[1.0.0]: https://github.com/Aminh0o/libraryManager/releases/tag/v1.0.0
