Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Env([string]$name) {
    $value = [Environment]::GetEnvironmentVariable($name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable($name, "User")
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing environment variable: $name"
    }

    Set-Item -Path "Env:$name" -Value $value
    return $value
}

function Invoke-Step([string]$command, [string]$workingDirectory) {
    Write-Host ""
    Write-Host ">> $command"
    Push-Location $workingDirectory
    try {
        cmd /c $command
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed (exit code $LASTEXITCODE): $command"
        }
    } finally {
        Pop-Location
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$androidDir = Join-Path $repoRoot "android"
$storeFile = Require-Env "ANDROID_UPLOAD_STORE_FILE"
[void](Require-Env "ANDROID_UPLOAD_STORE_PASSWORD")
[void](Require-Env "ANDROID_UPLOAD_KEY_ALIAS")
[void](Require-Env "ANDROID_UPLOAD_KEY_PASSWORD")
$expectedSha1 = Require-Env "ANDROID_UPLOAD_SHA1"

if (-not (Test-Path -LiteralPath $storeFile)) {
    throw "ANDROID_UPLOAD_STORE_FILE does not exist: $storeFile"
}

Write-Host "Using keystore: $storeFile"
Write-Host "Expected SHA1: $expectedSha1"

Invoke-Step ".\gradlew signingReport" $androidDir
Invoke-Step "flutter clean" $repoRoot
Invoke-Step "flutter pub get" $repoRoot
Invoke-Step "flutter build appbundle --release" $repoRoot

Write-Host ""
Write-Host "Release AAB build completed successfully."
