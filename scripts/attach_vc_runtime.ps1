<#
.SYNOPSIS
    Makes the Windows release folder self-contained by deploying the MSVC
    runtime app-local (next to library_manager.exe).

.DESCRIPTION
    WHY THIS EXISTS (bare-PC readiness).
    A byte-level import scan of the shipped binaries shows they all bind to the
    Visual C++ 2015-2022 runtime:

        library_manager.exe                   MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll
        sqlite3_flutter_libs_plugin.dll       VCRUNTIME140.dll
        sqlite3.dll                           VCRUNTIME140.dll
        printing_plugin.dll                   MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll
        url_launcher_windows_plugin.dll       MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll
        permission_handler_windows_plugin.dll MSVCP140.dll VCRUNTIME140.dll VCRUNTIME140_1.dll

    None of those DLLs ship with Windows. On a machine that has never had
    Visual Studio, or any other app that installs the redistributable, the
    program does not start at all -- Windows reports "code execution cannot
    proceed because VCRUNTIME140.dll was not found" before any Dart code runs.
    A library purchasing this product and installing it on the counter PC is
    exactly that machine.

    Two ways to fix it exist: run the VC_redist installer (needs admin and a
    second download), or deploy the runtime files beside the exe. This script
    does the latter, because the app-local copy needs no elevation, cannot
    conflict with a system-wide version, and is expressly permitted for
    redistributable components. The Windows DLL search order looks in the
    application directory first, so the bundled copies are the ones loaded.

    PROVENANCE. Prefer the copy that came with the Visual Studio installer
    (that is the officially redistributable package). Fall back to the
    system-wide copy installed by the redistributable, which is the same
    signed Microsoft binary at the same or newer version.

.EXAMPLE
    .\scripts\attach_vc_runtime.ps1
    .\scripts\attach_vc_runtime.ps1 -ReleaseDir build\windows\x64\runner\Release
#>

param(
    [string]$ReleaseDir = 'build\windows\x64\runner\Release'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Release directory not found: $ReleaseDir (run 'flutter build windows --release' first)"
    exit 1
}

# The three files every one of our binaries imports.
$runtimeFiles = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')

# Candidate sources, best provenance first. Only 64-bit directories qualify:
# a 32-bit runtime dropped beside a 64-bit exe still fails to load.
$vsRoots = @(
    "$env:ProgramFiles\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC*\VCRUNTIME140.dll",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\*\VC\Redist\MSVC\*\x64\Microsoft.VC*\VCRUNTIME140.dll",
    "$env:ProgramFiles\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC*\VCRUNTIME140.dll"
) | Where-Object { Test-Path $_ }

$sourceDirs = @()
foreach ($hit in $vsRoots) {
    # $hit is a pattern (VS embeds the compiler toolset version); resolve it to
    # the real directory so the log shows where the file actually came from.
    foreach ($match in (Resolve-Path -Path $hit -ErrorAction SilentlyContinue)) {
        $sourceDirs += Split-Path $match.Path -Parent
    }
}
# System32 holds the 64-bit copy on every Windows 10/11 box that has the
# redistributable installed (this build machine always does, it compiles with it).
$sourceDirs += "$env:SystemRoot\System32"
$sourceDirs = $sourceDirs | Select-Object -Unique

$attached = 0
$missing = @()

foreach ($file in $runtimeFiles) {
    $target = Join-Path $ReleaseDir $file
    if (Test-Path $target) {
        $v = (Get-Item $target).VersionInfo.FileVersion
        Write-Host "[=] already present: $file  (version $v)" -ForegroundColor DarkGray
        continue
    }

    $found = $null
    foreach ($dir in $sourceDirs) {
        $candidate = Join-Path $dir $file
        if (Test-Path $candidate) { $found = $candidate; break }
    }

    if ($null -eq $found) {
        $missing += $file
        continue
    }

    Copy-Item -Path $found -Destination $target -Force
    $v = (Get-Item $target).VersionInfo.FileVersion
    Write-Host "[+] attached $file  (version $v)  source: $(Split-Path $found -Parent)" -ForegroundColor Green
    $attached++
}

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Error ("Could not locate {0} on this machine. The installer would still " -f ($missing -join ', '))
    Write-Error 'require the Visual C++ 2015-2022 x64 redistributable on the target PC.'
    Write-Error 'Install VS Build Tools or place the redist DLLs where this script can find them.'
    exit 1
}

# Prove the claim rather than asserting it: re-scan the app binaries and confirm
# every imported MSVC runtime name now resolves inside the release folder.
$unresolved = @()
foreach ($bin in Get-ChildItem $ReleaseDir -Filter '*.exe') {
    $bytes = [System.IO.File]::ReadAllBytes($bin.FullName)
    $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
    foreach ($imported in ([regex]::Matches($text, 'MSVCP140\.dll|VCRUNTIME140(?:_1)?\.dll') |
        ForEach-Object { $_.Value } | Sort-Object -Unique)) {
        if (-not (Test-Path (Join-Path $ReleaseDir $imported))) {
            $unresolved += "$($bin.Name) -> $imported"
        }
    }
}

if ($unresolved.Count -gt 0) {
    Write-Error ("Unresolved runtime imports: " + ($unresolved -join '; '))
    exit 1
}

Write-Host ''
Write-Host "[OK] Release folder is self-contained: $($attached) runtime file(s) attached, no unresolved MSVC imports." -ForegroundColor Green
Write-Host '     The Setup package built from this folder installs on a Windows PC with nothing pre-installed.'
