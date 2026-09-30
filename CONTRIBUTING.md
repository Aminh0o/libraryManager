# Contributing to Library Manager

Thanks for taking the time to make this project better. This guide tells you
how to set up a development environment, what the codebase looks like, how we
format commits, and what CI will check before your pull request can merge.

---

## Code of conduct

Be kind. Be specific. Assume good faith. Critique the code, not the person.
Maintainers may close issues or PRs that violate these norms without
explanation.

---

## Getting set up

### Requirements

| Tool | Version | Notes |
| --- | --- | --- |
| Flutter SDK | 3.32.0+ (stable) | `flutter --version` to check |
| Dart SDK | ships with Flutter | must be 3.10.1+ |
| Visual Studio 2022 | Community or higher | workload: Desktop development with C++ |
| Windows 10 / 11 | x64 | this is a Windows-only target today |
| Git | any recent | |

### First-time clone

```powershell
git clone https://github.com/Aminh0o/libraryManager.git
cd library_manager
flutter pub get
flutter gen-l10n          # regenerates lib/l10n/app_localizations*.dart
flutter analyze           # must be zero-issues before you touch anything
flutter test              # 755+ tests, ~4 min
flutter run -d windows    # hot-reload loop
```

### Everyday loop

- Edit code.
- `flutter analyze` — the same gate CI enforces. Zero-issues or the PR
  does not merge.
- `flutter test` — full suite.
- For widget-level changes, `flutter run -d windows` and eyeball the app.

---

## Repository layout

```
lib/
  config/          — app-wide constants (network, version)
  domain/          — pure business rules: HoldPolicy, LoanPolicy, FineEngine
  l10n/            — ARB catalogues + generated AppLocalizations
  models/          — data classes; no logic beyond normalisation
  providers/       — ChangeNotifier layer; how UI observes state
  screens/         — full-screen routes
  services/        — DatabaseService, ApiService, AuthService, HTTP server
  ui/              — theme, tokens, spacing
  utils/           — small pure helpers (AppDate, DisplaySafety)
  widgets/         — reusable widgets shared by screens
test/              — mirrors lib/, one _test.dart per source file
windows/           — native runner (rarely edited)
.github/           — issue & PR templates, Actions workflows
```

Two rules that keep this structure honest:

1. **`lib/screens/` is a thin shell.** It never computes a figure, filters a
   report row, or reimplements a domain rule. All logic lives in
   `lib/domain/` or `lib/services/` so the UI, the HTTP server and the CSV
   / PDF export can never disagree.
2. **The repository seam is sacred.** Providers talk to
   `LibraryRepository`, never directly to SQLite or HTTP. The seam is what
   lets a host and a client share the same provider code.

---

## Coding style

The lint set in `analysis_options.yaml` is authoritative. Beyond that:

- **Prefer explicit over clever.** `switch` expressions are fine; recursive
  generics with variance annotations are not.
- **Named parameters everywhere** for anything with more than two positional
  arguments.
- **Comments explain *why*, not *what*.** If a line obviously does what it
  does, no comment. If a line exists to dodge a Flutter bug, add a
  paragraph and a link.
- **No dead code, no commented-out blocks.** Git remembers.
- **Every public class and top-level function gets a doc-comment** starting
  with the class name so hover in IDEs reads well.
- **Localisation keys** live in `lib/l10n/app_en.arb` first, then get
  mirrored into `app_fr.arb` and `app_ar.arb`. Never hard-code a user-facing
  string; the l10n parity test will fail.

### Formatting

```powershell
dart format .
```

Runs before every commit; the CI workflow re-checks it.

---

## Testing

- Every new feature lands with tests. Every bug fix lands with a regression
  test that fails on the previous HEAD and passes on yours.
- Naming convention: `test/<area>/<subject>_test.dart` mirrors
  `lib/<area>/<subject>.dart`.
- Prefer behaviour-first test names:

  ```dart
  test('a viewer session is refused the delete endpoint even when it forges',
  ```

  not `test('testDeleteViewer')`.
- Widget tests must go through the real provider stack, not a stub, so a
  regression in the provider is caught by the widget test as well.
- Test the *invariant*, not the implementation — a test that only passes
  because a private method happens to return a specific string is a bad
  test.

Run the suite:

```powershell
flutter test
```

Run a single file:

```powershell
flutter test test/services/auth_service_test.dart
```

---

## Localisation

- ARB catalogues live in `lib/l10n/app_en.arb`, `app_fr.arb`, `app_ar.arb`.
- After editing any ARB, run `flutter gen-l10n`. The generated files under
  `lib/l10n/app_localizations*.dart` are **tracked in git** — commit them
  with your ARB changes so `flutter pub get` on a downstream machine works
  without a separate gen step.
- Placeholder keys require a matching `@<key>` metadata block with a
  `placeholders` field, or the generator emits `String` positional args
  instead of named args.
- Arabic requires RTL-safe layout. If a screen uses `Row` for something
  directional, wrap it so `Directionality` reverses correctly, or use
  `Icon(Icons.arrow_back, matchTextDirection: true)` where relevant.

---

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/).

```
<type>(<scope>): <imperative summary, ≤ 72 chars>

<optional body — what changed, why, and what to review carefully>

<optional footer — BREAKING CHANGE: ..., Fixes #123, etc.>
```

Types:

| Type | Meaning |
| --- | --- |
| `feat` | A new user-facing capability. |
| `fix` | A bug fix. |
| `perf` | A performance improvement. |
| `refactor` | Neither a fix nor a feature. |
| `docs` | Documentation only. |
| `test` | Test-only change. |
| `chore` | Build, tooling, deps. |
| `ci` | GitHub Actions or CI configuration. |
| `revert` | Reverts a previous commit. |

Examples of the standard we hold ourselves to:

```
fix(circulation): gate Confirm Return on empty barcode

Previously the Confirm Return FilledButton was enabled even when the
barcode field was empty, so an operator scanning nothing would click
Return and see nothing happen — no error, no toast, no state change.
The transaction silently dropped.

The button is now disabled whenever the controller text is empty,
matching the pattern used by every other submit in the app. The
controller listens for changes and calls setState so the enabled
flag is reactive.

Fixes #481.
```

```
feat(reports): route Generated header through AppDate

The engine stores generated_at as an ISO-8601 string and the screen
rendered it verbatim, so operators saw
"Generated 2026-09-29T23:30:35.331300". Fall back to the raw value if
the string is unparseable, so a hand-edited legacy row never crashes
the screen.
```

Rules of thumb:

- **One logical change per commit.** A drive-by rename does not ride along
  with a bug fix.
- **Summarise the outcome, not the file.** `fix: user can no longer
  double-check-out` beats `fix: library_provider.dart bug`.
- Reference issues (`Fixes #`, `Ref #`) so GitHub cross-links them.

---

## Pull requests

- Fill in the PR template. If you cannot answer one of its questions, that
  is a signal the change is not ready.
- Keep PRs under ~400 lines of non-generated diff. Larger work should be
  split into a stack.
- Screenshots or a short `.mp4` are required for any UI change.
- The CI matrix (analyze + test + build) must be green before we ask for
  review.
- A maintainer will label your PR (`bug`, `enhancement`, `needs-test`,
  `do-not-merge-yet`) within 72 hours.

---

## Reviewing

- Reviewers approve the diff, not the author.
- Comment on code, not intent. "This line dereferences a nullable without
  a null check" beats "why did you do this".
- Silent LGTM is fine for a purely cosmetic change.
- For anything touching authentication, authorisation, backup / restore
  or the HTTP contract, **at least one maintainer must review** before
  merge.

---

## Cutting a release

Releases are tagged from `main` and published automatically by the
`.github/workflows/release.yml` workflow, which triggers on any tag
matching `v*.*.*`:

```powershell
git checkout main
git pull --ff-only
# 1. bump pubspec.yaml version and lib/config/app_info.dart in lock-step
# 2. update CHANGELOG.md: move items out of "Unreleased" into the new heading
git commit -am "chore(release): v1.2.0"
git tag v1.2.0
git push origin main --follow-tags
```

The Actions job will build the Windows bundle, zip it, and attach it to a
GitHub Release titled after the tag. Watch the run to make sure the checksum
line is populated.

---

## Getting help

- Open a **Discussion** for questions about design or usage.
- Open an **Issue** only for a reproducible defect or a specific, scoped
  feature request. Use the templates.
- For anything security-sensitive, read `SECURITY.md` and email the
  private-disclosure address instead of opening a public issue.

Thanks for reading this far. Small, careful, well-tested changes are the
whole game.
