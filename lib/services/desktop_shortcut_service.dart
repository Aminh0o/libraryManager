import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service to update the Windows Desktop and Start Menu application shortcuts
/// when the operator re-brands the library name or custom logo/icon.
class DesktopShortcutService {
  const DesktopShortcutService._();

  /// Updates or creates the Windows Desktop shortcut with [appTitle] and optional [iconPath].
  static Future<void> syncShortcut({
    required String appTitle,
    String? iconPath,
  }) async {
    if (!Platform.isWindows) return;

    try {
      final exePath = Platform.resolvedExecutable;
      final safeTitle = appTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
      final titleToUse = safeTitle.isEmpty ? 'Library Manager' : safeTitle;

      final script =
          '''
\$ErrorActionPreference = 'SilentlyContinue'
\$shell = New-Object -ComObject WScript.Shell
\$targetExe = '$exePath'
\$newTitle = '$titleToUse'
\$customIcon = '${iconPath ?? ''}'

\$folders = @(
  [Environment]::GetFolderPath('Desktop'),
  [Environment]::GetFolderPath('CommonDesktopDirectory'),
  [Environment]::GetFolderPath('Programs'),
  [Environment]::GetFolderPath('CommonPrograms')
)

\$updated = \$false

foreach (\$folder in \$folders) {
  if ([string]::IsNullOrWhiteSpace(\$folder) -or !(Test-Path \$folder)) { continue }
  
  # Search for any existing shortcut pointing to our executable
  Get-ChildItem -Path \$folder -Filter '*.lnk' -Recurse | ForEach-Object {
    try {
      \$s = \$shell.CreateShortcut(\$_.FullName)
      if (\$s.TargetPath -and (\$s.TargetPath -eq \$targetExe -or \$s.TargetPath -like '*library_manager.exe*')) {
        \$s.Description = \$newTitle
        if (\$customIcon -and (Test-Path \$customIcon)) {
          \$s.IconLocation = "\$customIcon,0"
        }
        \$s.Save()
        
        # Rename shortcut file to match brand title if different
        \$dir = \$_.DirectoryName
        \$desiredPath = Join-Path \$dir "\$newTitle.lnk"
        if (\$_.FullName -ne \$desiredPath -and !(Test-Path \$desiredPath)) {
          Rename-Item -Path \$_.FullName -NewName "\$newTitle.lnk" -Force
        }
        \$updated = \$true
      }
    } catch {}
  }
}

# If no desktop shortcut existed, create a fresh one on User Desktop
if (!\$updated) {
  \$userDesktop = [Environment]::GetFolderPath('Desktop')
  if (Test-Path \$userDesktop) {
    \$lnkPath = Join-Path \$userDesktop "\$newTitle.lnk"
    \$s = \$shell.CreateShortcut(\$lnkPath)
    \$s.TargetPath = \$targetExe
    \$s.WorkingDirectory = Split-Path \$targetExe
    \$s.Description = \$newTitle
    if (\$customIcon -and (Test-Path \$customIcon)) {
      \$s.IconLocation = "\$customIcon,0"
    }
    \$s.Save()
  }
}
''';

      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
    } catch (e) {
      debugPrint('DesktopShortcutService: Failed to sync shortcut: $e');
    }
  }
}
