# cycling

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android Release Signing (Google Play)

This project blocks release builds when the upload keystore fingerprint is wrong.

- Expected upload SHA1: `CD:95:22:8D:BB:BF:EB:60:25:91:DE:00:36:87:8A:64:B1:32:66:86`
- Release build fails immediately if a different keystore is used.

### 1) Configure signing values

Use one of the following:

- Environment variables (recommended)
  - `ANDROID_UPLOAD_STORE_FILE`
  - `ANDROID_UPLOAD_STORE_PASSWORD`
  - `ANDROID_UPLOAD_KEY_ALIAS`
  - `ANDROID_UPLOAD_KEY_PASSWORD`
  - Optional override: `ANDROID_UPLOAD_SHA1`
- or `android/key.properties` (local-only, never commit)
  - Optional: `expectedSha1`

You can copy `android/key.properties.example` and rename it to `android/key.properties`.

### 2) Verify keystore fingerprint

From `android` directory:

- `./gradlew signingReport`

Check `Variant: release` SHA1 and make sure it matches the expected upload SHA1.

### 3) Build release App Bundle

- `flutter clean`
- `flutter pub get`
- `flutter build appbundle --release`

### Windows one-time setup and build

From project root in PowerShell:

- `powershell -ExecutionPolicy Bypass -File .\tools\setup_android_upload_env.ps1 -StoreFile "D:\path\to\upload-keystore.jks" -KeyAlias "upload"`
- `powershell -ExecutionPolicy Bypass -File .\tools\build_release_aab.ps1`
