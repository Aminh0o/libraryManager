<#
.SYNOPSIS
    Builds the portable (no-installer) Windows bundle that the in-app updater
    and the release page publish.

.DESCRIPTION
    Produces exactly the artifact name the app's own updater looks for on a
    GitHub release - the first .zip asset carrying a browser_download_url, plus
    a sibling "<name>.sha256sum" - from a release folder that
    scripts/attach_vc_runtime.ps1 has already made self-contained.

    Run scripts/build_installer.ps1 for the Setup package; both consume the same
    build\windows\x64\runner\Release folder, so build them from one build to keep
    the installer and the portable bundle byte-identical in content.

.EXAMPLE
    .\scripts\build_portable_zip.ps1
    .\scripts\build_portable_zip.ps1 -Version 1.2.0
#>

param(
    [string]$Version = '1.2.0',
    [string]$ReleaseDir = 'build\windows\x64\runner\Release',
    [string]$OutDir = 'dist'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $ReleaseDir 'library_manager.exe'))) {
    Write-Error "No library_manager.exe in $ReleaseDir - run 'flutter build windows --release' first."
    exit 1
}

# The same guard the installer builder applies: refuse to publish a bundle whose
# binaries import an MSVC runtime that is not sitting next to them.
& 'powershell.exe' -ExecutionPolicy Bypass -File 'scripts\attach_vc_runtime.ps1' -ReleaseDir $ReleaseDir
if ($LASTEXITCODE -ne 0) {
    Write-Error 'Refusing to build the portable bundle: the release folder is not self-contained.'
    exit 1
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$zip = Join-Path $OutDir "LibraryManager-$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

# Contents sit at the zip root (data\, *.dll, library_manager.exe) - the folder
# layout the README's "unzip anywhere and run" instruction describes, and the
# layout every previously published bundle used.
Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $zip -CompressionLevel Optimal

$hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
# GNU binary-mode line, matching the installer builder and the updater parser.
"$hash *$(Split-Path $zip -Leaf)" | Out-File -FilePath "$zip.sha256sum" -Encoding ascii -NoNewline

Write-Host ''
Write-Host "[OK] $zip  ($([math]::Round((Get-Item $zip).Length / 1MB, 2)) MB)" -ForegroundColor Green
Write-Host "     SHA256: $hash"
Write-Host "     Checksum file: $zip.sha256sum"
