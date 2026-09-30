/// ARC-06: a single source for the human-facing app version used by the
/// diagnostics bundle header. Keep this in step with `pubspec.yaml`'s
/// `version:` line; it is intentionally a plain constant (no package_info_plus
/// dependency) so a release build's diagnostics never fail on a missing plugin.
const String kAppVersion = '1.1.2+6';
