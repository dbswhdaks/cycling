param(
    [Parameter(Mandatory = $true)]
    [string]$StoreFile,

    [Parameter(Mandatory = $false)]
    [string]$KeyAlias = "upload",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedSha1 = "CD:95:22:8D:BB:BF:EB:60:25:91:DE:00:36:87:8A:64:B1:32:66:86"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainText([Security.SecureString]$secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not (Test-Path -LiteralPath $StoreFile)) {
    throw "Keystore file not found: $StoreFile"
}

$storePasswordSecure = Read-Host "Keystore password" -AsSecureString
$keyPasswordSecure = Read-Host "Key password" -AsSecureString

$storePassword = ConvertTo-PlainText $storePasswordSecure
$keyPassword = ConvertTo-PlainText $keyPasswordSecure

if ([string]::IsNullOrWhiteSpace($storePassword)) {
    throw "Keystore password cannot be empty."
}
if ([string]::IsNullOrWhiteSpace($keyPassword)) {
    throw "Key password cannot be empty."
}
if ([string]::IsNullOrWhiteSpace($KeyAlias)) {
    throw "Key alias cannot be empty."
}

$resolvedStoreFile = (Resolve-Path -LiteralPath $StoreFile).Path

# Persist for next terminals/sessions
[Environment]::SetEnvironmentVariable("ANDROID_UPLOAD_STORE_FILE", $resolvedStoreFile, "User")
[Environment]::SetEnvironmentVariable("ANDROID_UPLOAD_STORE_PASSWORD", $storePassword, "User")
[Environment]::SetEnvironmentVariable("ANDROID_UPLOAD_KEY_ALIAS", $KeyAlias, "User")
[Environment]::SetEnvironmentVariable("ANDROID_UPLOAD_KEY_PASSWORD", $keyPassword, "User")
[Environment]::SetEnvironmentVariable("ANDROID_UPLOAD_SHA1", $ExpectedSha1, "User")

# Also apply for current PowerShell session
$env:ANDROID_UPLOAD_STORE_FILE = $resolvedStoreFile
$env:ANDROID_UPLOAD_STORE_PASSWORD = $storePassword
$env:ANDROID_UPLOAD_KEY_ALIAS = $KeyAlias
$env:ANDROID_UPLOAD_KEY_PASSWORD = $keyPassword
$env:ANDROID_UPLOAD_SHA1 = $ExpectedSha1

Write-Host ""
Write-Host "Saved user environment variables:"
Write-Host " - ANDROID_UPLOAD_STORE_FILE=$resolvedStoreFile"
Write-Host " - ANDROID_UPLOAD_KEY_ALIAS=$KeyAlias"
Write-Host " - ANDROID_UPLOAD_SHA1=$ExpectedSha1"
Write-Host ""
Write-Host "Next step:"
Write-Host " powershell -ExecutionPolicy Bypass -File .\tools\build_release_aab.ps1"
