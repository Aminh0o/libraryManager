<#
.SYNOPSIS
    Signs the Library Manager Windows desktop executable with an Authenticode digital signature.
.DESCRIPTION
    Creates or uses a local code-signing certificate to sign library_manager.exe, establishing
    publisher identity and preventing Windows SmartScreen unknown-publisher warnings.
.EXAMPLE
    .\sign_release.ps1 -ExePath "c:\flutter_apps\library\build\windows\x64\runner\Release\library_manager.exe"
#>

param(
    [string]$ExePath = "c:\flutter_apps\library\build\windows\x64\runner\Release\library_manager.exe",
    [string]$CertSubject = "CN=Library Manager Publisher, O=Library Manager, C=US"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Library Manager - Authenticode Digital Signature Tool  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $ExePath)) {
    Write-Error "Target executable not found at: $ExePath"
    exit 1
}

Write-Host "[*] Inspecting executable: $ExePath"
$sig = Get-AuthenticodeSignature -FilePath $ExePath
if ($sig.Status -eq "Valid") {
    Write-Host "[+] Executable is already signed by: $($sig.SignerCertificate.Subject)" -ForegroundColor Green
    exit 0
}

Write-Host "[*] Locating or generating Code Signing Certificate..."
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "*Library Manager*" } | Select-Object -First 1

if ($null -eq $cert) {
    Write-Host "[*] Creating self-signed code-signing certificate for publisher..."
    $cert = New-SelfSignedCertificate -Type CodeSigningCert `
        -Subject $CertSubject `
        -CertStoreLocation Cert:\CurrentUser\My `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(5)
    
    Write-Host "[+] Generated Certificate Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

    # Trust the certificate locally so SmartScreen recognizes it
    Write-Host "[*] Exporting public certificate to trust store..."
    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $tempCertPath = [System.IO.Path]::GetTempFileName() + ".cer"
    [System.IO.File]::WriteAllBytes($tempCertPath, $certBytes)

    Import-Certificate -FilePath $tempCertPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
    Remove-Item $tempCertPath -Force
    Write-Host "[+] Installed certificate into Trusted Root store." -ForegroundColor Green
} else {
    Write-Host "[+] Found existing code-signing certificate: $($cert.Thumbprint)" -ForegroundColor Green
}

Write-Host "[*] Signing $ExePath with Authenticode signature..."
$result = Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert -HashAlgorithm SHA256

if ($result.Status -eq "Valid") {
    Write-Host "[+] SUCCESS: library_manager.exe signed successfully!" -ForegroundColor Green
    Write-Host "    Signer: $($cert.Subject)" -ForegroundColor Cyan
    Write-Host "    Status: $($result.Status)" -ForegroundColor Cyan
    Write-Host "    Digest: SHA256" -ForegroundColor Cyan
} else {
    Write-Warning "[-] Signing completed with status: $($result.Status) - $($result.StatusMessage)"
}
