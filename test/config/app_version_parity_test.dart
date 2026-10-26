import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Release hygiene gate: ONE version number, four places that must agree.
///
/// The version is stamped into `pubspec.yaml` (the Dart app), `kAppVersion`
/// (diagnostics bundle header + the About surface), the Inno Setup script
/// (`AppVersion`, the file-version resource on Setup.exe) and the installer
/// builder's default `-Version`. Before this test those were edited by hand
/// and had already drifted once, which produces the worst kind of release
/// bug: a shipped installer whose About box and Support ticket diagnostics
/// name a version the build system never produced.
///
/// This test reads the source files directly (no parsing library, no build
/// artifacts) so it fails loudly on a version bump done in only one place.
void main() {
  String read(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$path must exist in the repo root',
    );
    return file.readAsStringSync();
  }

  test('pubspec, kAppVersion, installer script and installer builder agree', () {
    final pubspec = read('pubspec.yaml');
    final pubMatch = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(
      pubMatch,
      isNotNull,
      reason: 'pubspec.yaml needs a version: X.Y.Z+N',
    );
    final semver = pubMatch!.group(1)!;
    final build = pubMatch.group(2)!;

    final appInfo = read('lib/config/app_info.dart');
    final appMatch = RegExp(
      r"const String kAppVersion = '(\d+\.\d+\.\d+)\+(\d+)';",
    ).firstMatch(appInfo);
    expect(
      appMatch,
      isNotNull,
      reason: 'kAppVersion must be a literal X.Y.Z+N',
    );
    expect(
      '${appMatch!.group(1)}+${appMatch.group(2)}',
      '$semver+$build',
      reason:
          'kAppVersion is the version printed in diagnostics and on the About '
          'surface; it must equal pubspec.yaml.',
    );

    final iss = read('installer/library_manager.iss');
    final issVersion = RegExp(
      r'#define MyAppVersion "(\d+\.\d+\.\d+)"',
    ).firstMatch(iss);
    final issBuild = RegExp(r'#define MyAppBuild "(\d+)"').firstMatch(iss);
    expect(
      issVersion,
      isNotNull,
      reason: 'installer needs #define MyAppVersion',
    );
    expect(issBuild, isNotNull, reason: 'installer needs #define MyAppBuild');
    expect(issVersion!.group(1), semver);
    expect(issBuild!.group(1), build);

    // The Setup.exe file-version resource is "<semver>.<build>".
    expect(
      RegExp(
        r'^VersionInfoVersion=\{#MyAppVersion\}\.\{#MyAppBuild\}$',
        multiLine: true,
      ).hasMatch(iss),
      isTrue,
      reason:
          'VersionInfoVersion must derive from the defines, not be hard-coded',
    );

    final ps1 = read('scripts/build_installer.ps1');
    final psMatch = RegExp(
      r'\[string\]\$Version = "(\d+\.\d+\.\d+)"',
    ).firstMatch(ps1);
    expect(
      psMatch,
      isNotNull,
      reason: 'build_installer needs a default version',
    );
    expect(
      psMatch!.group(1),
      semver,
      reason:
          'The installer builder names the output file; a stale default emits '
          'a Setup package labelled with the previous release.',
    );
  });

  test('installer carries exactly one AppVersion directive', () {
    final iss = read('installer/library_manager.iss');
    final count = RegExp(
      r'^AppVersion=',
      multiLine: true,
    ).allMatches(iss).length;
    expect(
      count,
      1,
      reason:
          'a duplicated [Setup] directive makes the stamped version '
          'depend on Inno\'s key-override order — pick one.',
    );
  });
}
