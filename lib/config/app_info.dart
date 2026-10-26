/// ARC-06: a single source for the human-facing app version used by the
/// diagnostics bundle header. Keep this in step with `pubspec.yaml`'s
/// `version:` line; it is intentionally a plain constant (no package_info_plus
/// dependency) so a release build's diagnostics never fail on a missing plugin.
const String kAppVersion = '1.2.0+10';

/// Phase 11 branding: the product is published under Evenlio. These are the
/// ONLY contact details verified from the public site (www.evenlio.com / its
/// contact page) at the time of writing — Evenlio's own page lists the postal
/// address and phone as "to be updated soon", so we deliberately surface
/// neither here rather than invent one. Keep this the single source so the
/// Help Center footer and any future About surface render identical details.
const String kBrandName = 'Evenlio';
const String kBrandUrl = 'https://www.evenlio.com';
const String kBrandEmail = 'evenlio.contact@gmail.com';
