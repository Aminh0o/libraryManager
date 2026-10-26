; Script for Library Manager (Inno Setup 6). Built by scripts\build_installer.ps1,
; which first makes the release folder self-contained (see Attach step below).

#define MyAppName "Library Manager"
#define MyAppVersion "1.2.0"
#define MyAppBuild "10"
#define MyAppPublisher "Evenlio"
#define MyAppURL "https://github.com/Aminh0o/libraryManager"
#define MyAppSupportURL "https://www.evenlio.com"
#define MyAppExeName "library_manager.exe"
#define MyAppSourceDir "..\build\windows\x64\runner\Release"
#define MyAppIcon "..\windows\runner\resources\app_icon.ico"

[Setup]
; AppId is a unique GUID identifying this application across updates
AppId={{8B5C3847-E8B2-4E83-96E8-897F29B5DE63}}
AppName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppURL}/releases
AppVersion={#MyAppVersion}+{#MyAppBuild}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
; Privileges: lowest by default with dialog override allows standard users OR administrators to install
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Install in native 64-bit mode so registry entries and {autopf} resolve to the 64-bit view
ArchitecturesInstallIn64BitMode=x64compatible
; File version resource stamped on Setup.exe itself (major.minor.patch.build)
VersionInfoVersion={#MyAppVersion}.{#MyAppBuild}
; Inno requires both of these as plain numeric versions, so the pubspec build
; number is used as the fourth part instead of the "+" form the Dart side uses.
VersionInfoProductVersion={#MyAppVersion}.{#MyAppBuild}
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}
OutputDir=..\dist
OutputBaseFilename=LibraryManager-Setup-{#MyAppVersion}-windows-x64
SetupIconFile={#MyAppIcon}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole release folder ships as-is. That folder ALSO contains
; vcruntime140.dll / vcruntime140_1.dll / msvcp140.dll, copied in by
; scripts\attach_vc_runtime.ps1 before this script runs. Those files are what
; lets the program start on a Windows PC that has never had Visual Studio or
; the Visual C++ redistributable installed; without them Windows refuses to
; launch the exe at all. Do not remove them from the build output.
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
