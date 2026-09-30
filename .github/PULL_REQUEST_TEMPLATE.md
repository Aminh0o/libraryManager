# What and why

<!--
  One paragraph. What does this PR change, and what user-visible outcome does
  it produce? If this closes an issue, link it below with `Fixes #`.
-->

Fixes #____

# Type of change

- [ ] `fix:` — bug fix (no behaviour change for users who never hit the bug)
- [ ] `feat:` — new user-facing capability
- [ ] `perf:` — performance improvement
- [ ] `refactor:` — neither a fix nor a feature
- [ ] `docs:` — documentation only
- [ ] `test:` — test-only change
- [ ] `chore:` — build, tooling, dependency bump
- [ ] `ci:` — GitHub Actions / workflow changes
- [ ] **breaking change** — schema, HTTP contract, or public API

# Scope

- [ ] Only touches presentation (`lib/screens/`, `lib/widgets/`, `lib/ui/`)
- [ ] Touches domain or provider (`lib/domain/`, `lib/providers/`)
- [ ] Touches services (SQLite, HTTP, auth, backups)
- [ ] Touches the HTTP contract (`lib/services/api_contract.dart`, `http_server_service.dart`)
- [ ] Touches the ARB catalogues (EN / FR / AR)

# Screenshots / recording

<!-- Required for any UI change. Attach an image or a short mp4. -->

# Test plan

- [ ] `flutter analyze` reports zero issues
- [ ] `flutter test` passes locally (paste the final `+NNN: All tests passed!` line below)
- [ ] Regression test added that **fails on `main`** and passes on this branch
- [ ] Manual walkthrough on `flutter run -d windows` (describe below)
- [ ] If UI: verified in EN, FR and AR, RTL layout intact
- [ ] If HTTP / auth: host + client pair tested against real LAN, not localhost

```
paste `flutter test` tail here
```

# What a reviewer should look at carefully

<!--
  Point the reviewer at the parts you are least confident about, or that
  have non-obvious implications: migrations, CAS ordering, throttle windows,
  anything that could strand an existing install.
-->

# Migration & upgrade notes

<!--
  If the SQLite schema changes, describe the defensive migration and the
  rollback path. If the HTTP contract changes, state whether old clients
  can still talk to a new host and vice versa.
-->

- [ ] No migration required (byte-compatible with previous release)
- [ ] Additive migration only (old clients work against a new host)
- [ ] Requires host restart; old clients refuse with a clear error
- [ ] Requires schema migration; **backup is taken automatically before upgrade**

# Security & privacy

- [ ] No new secret, token, salt or PII is logged
- [ ] No new network endpoint without an authorisation check on the server side
- [ ] Diagnostics bundle still redacts usernames, emails and item codes

# Contributor checklist

- [ ] I have read `CONTRIBUTING.md`
- [ ] Commits follow Conventional Commits
- [ ] One logical change per commit
- [ ] No dead code, no commented-out blocks
- [ ] Every new / changed l10n key is present in EN, FR and AR with matching placeholders
- [ ] My branch is rebased onto current `main`
