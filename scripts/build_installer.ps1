<#
.SYNOPSIS
    Compiles and signs the professional Windows Setup Installer for Library Manager.
.DESCRIPTION
    Uses Inno Setup Compiler (ISCC.exe) to generate a native Setup.exe from installer/library_manager.iss,
    signs the installer with Authenticode SHA-256 digital signature, and writes SHA-256 checksums.
.EXAMPLE
    .\scripts\build_installer.ps1
#>

param(
    [string]$Version = "1.1.5"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Library Manager - Windows Setup Installer Builder     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Locate ISCC.exe
$isccPaths = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)

$iscc = $null
foreach ($path in $isccPaths) {
    if (Test-Path $path) {
        $iscc = $path
        break
    }
}

if ($null -eq $iscc) {
    # Check PATH
    $cmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        $iscc = $cmd.Source
    }
}

if ($null -eq $iscc) {
    Write-Error "Inno Setup Compiler (ISCC.exe) not found. Please install Inno Setup 6."
    exit 1
}

Write-Host "[+] Found Inno Setup Compiler: $iscc" -ForegroundColor Green

# 2. Verify target release binary exists
$exePath = "build\windows\x64\runner\Release\library_manager.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "[*] Release binary not found. Building with Flutter..." -ForegroundColor Yellow
    flutter.bat build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows release build failed."
        exit 1
    }
}

# 3. Ensure executable is signed
Write-Host "[*] Verifying Authenticode signature on $exePath..."
$sig = Get-AuthenticodeSignature -FilePath $exePath
if ($sig.Status -eq "NotSigned" -or $null -eq $sig.SignerCertificate) {
    Write-Host "[*] Signing $exePath with scripts/sign_release.ps1..." -ForegroundColor Yellow
    & "powershell.exe" -ExecutionPolicy Bypass -File "scripts\sign_release.ps1"
}

# 4. Ensure dist directory exists
if (-not (Test-Path "dist")) {
    New-Item -ItemType Directory -Path "dist" -Force | Out-Null
}

# 5. Compile Inno Setup Script
Write-Host "[*] Compiling installer script: installer\library_manager.iss..."
& $iscc "installer\library_manager.iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ISCC installer compilation failed."
    exit 1
}

$installerExe = "dist\LibraryManager-Setup-$Version-windows-x64.exe"
if (-not (Test-Path $installerExe)) {
    Write-Error "Expected installer output not found: $installerExe"
    exit 1
}

$installerSize = (Get-Item $installerExe).Length
Write-Host "[+] Installer successfully created: $installerExe ($([math]::Round($installerSize / 1MB, 2)) MB)" -ForegroundColor Green

# 6. Sign the installer executable itself
Write-Host "[*] Signing installer executable with Authenticode..."
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "*Library Manager*" } | Select-Object -First 1

if ($cert) {
    $signResult = Set-AuthenticodeSignature -FilePath $installerExe -Certificate $cert -HashAlgorithm SHA256
    Write-Host "[+] Signed installer with thumbprint: $($cert.Thumbprint) (Status: $($signResult.Status))" -ForegroundColor Green
} else {
    Write-Warning "[-] No Library Manager code signing certificate found in Cert:\CurrentUser\My; installer left unsigned."
}

# 7. Compute SHA-256 Checksum
Write-Host "[*] Computing SHA-256 digest..."
$hash = (Get-FileHash -Path $installerExe -Algorithm SHA256).Hash
"$hash *$(Split-Path $installerExe -Leaf)" | Out-File -FilePath "$installerExe.sha256sum" -Encoding ascii -NoNewline

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   INSTALLER BUILD COMPLETE                              " -ForegroundColor Cyan
Write-Host "   File:   $installerExe" -ForegroundColor Green
Write-Host "   Size:   $([math]::Round($installerSize / 1MB, 2)) MB" -ForegroundColor Green
Write-Host "   SHA256: $hash" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
