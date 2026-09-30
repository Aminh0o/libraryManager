# Changelog

All notable changes to **Library Manager** are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
  salt and 210 000 rounds; last-admin guard; reserved-name guard.
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
