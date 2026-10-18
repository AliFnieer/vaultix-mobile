# Vaultix Mobile

[![Flutter CI](https://github.com/AliFnieer/vaultix-mobile/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AliFnieer/vaultix-mobile/actions/workflows/ci.yml)

Vaultix Mobile is a Flutter client for the Vaultix password-management
backend. It provides an encrypted local vault, account access, and
device-managed authenticator entries.

> **Status:** Development project. The CI workflow builds native platform
> artifacts; these are not automatically signed or published to app stores.

## Features

- Account registration, sign-in, session handling, and vault locking.
- Offline-first vault items with local persistence and backend synchronization.
- Encrypted local database and AES-GCM protection for locally stored secret
  fields.
- Device-only authenticator entries and QR scanning.
- Light and dark Material themes, with Inter bundled locally.

Authenticator entries are stored on the device; the backend does not currently
provide MFA or server-backed TOTP endpoints. Vaultix Mobile does not claim
zero-knowledge encryption: review the backend's data handling and the security
assumptions for your deployment before storing sensitive information.

## Supported platforms

| Platform | CI build | Notes |
| --- | --- | --- |
| Android | APK and AAB | Configure release signing before distribution. |
| iOS | Unsigned app bundle | Requires Apple signing for installation and distribution. |
| Linux | Release bundle | Requires GTK and libsecret runtime dependencies. |
| macOS | Release app bundle | Configure signing and notarization for distribution. |
| Windows | Release bundle | Package the output directory with its runtime files. |

Web is not supported because the application uses native database and FFI
dependencies.

## Requirements

- Flutter stable (the CI workflow currently uses Flutter 3.47.7).
- A reachable Vaultix backend.
- Platform-specific toolchains when building outside GitHub Actions:
  Android SDK/JDK for Android, Xcode for Apple platforms, GTK development
  packages for Linux, or Visual Studio with C++ desktop support for Windows.

## Getting started

```sh
git clone https://github.com/AliFnieer/vaultix-mobile.git
cd vaultix-mobile
flutter pub get
flutter run
```

By default, the app targets `http://192.168.1.59:8080`, your backend's address
on the local network. Set `API_BASE_URL` to a different backend address when
needed:

```sh
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

For local development, copy `.env.example` to `.env` and set `API_BASE_URL`.
Flutter does not load `.env` automatically; pass its value as a compile-time
define. For example, in Bash:

```sh
set -a
. ./.env
set +a
flutter run --dart-define="API_BASE_URL=$API_BASE_URL"
```

Or in PowerShell:

```powershell
$env:API_BASE_URL = "https://api.example.com"
flutter run --dart-define="API_BASE_URL=$env:API_BASE_URL"
```

The local `.env` file is ignored by Git. Do not put passwords, signing keys,
tokens, or other credentials in it or in `--dart-define`; compile-time values
are embedded in the application. Use HTTPS for non-local backend connections.

## Project structure

```text
lib/
  app.dart                 App theme and navigation
  core/
    api/                   Backend API clients and models
    config/                Compile-time configuration
    crypto/                Key derivation and cryptographic helpers
    data/                  Repositories
    db/                    Encrypted local database
    di/                    Riverpod providers
    sync/                  Offline synchronization
    theme/                 Shared Material design system
  features/
    auth/                  Authentication and vault lifecycle
    settings/              App settings
    totp/                  Device authenticator
    vault/                 Vault and secret-item screens
test/                      Unit and widget tests
.github/workflows/         GitHub Actions CI and native builds
```

## Checks and builds

Run the local checks:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Build a platform locally (use the matching platform toolchain):

```sh
flutter build apk --release
flutter build appbundle --release
flutter build linux --release
flutter build macos --release
flutter build windows --release
flutter build ios --release --no-codesign
```

The [Flutter CI workflow](https://github.com/AliFnieer/vaultix-mobile/actions/workflows/ci.yml)
runs formatting, analysis, and tests, then builds native artifacts for Android,
iOS, Linux, macOS, and Windows. It runs for pull requests and pushes to `main`
or `dev`; version tags matching `v*` and manual runs are also supported. Build
artifacts are retained by GitHub Actions for 14 days.

Set the repository Actions variable `API_BASE_URL` under **Settings → Secrets
and variables → Actions → Variables** to use a backend URL in CI builds. If
unset, the workflow uses the Android emulator default.
