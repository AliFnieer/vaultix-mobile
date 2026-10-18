# Vaultix Mobile

Vaultix is a Flutter password manager and authenticator client for the
Vaultix backend. It uses a Flutter-native architecture designed around secure
local storage, backend integration, and cross-platform support.

## Design system

The Flutter theme defines light and dark palettes, Inter typography, gold
primary actions, green secondary accents, soft surfaces, and rounded
controls. It follows the device theme by default. Inter is bundled locally so
the interface does not fetch fonts at runtime; its SIL Open Font License is in
`assets/fonts/OFL.txt`.

Vaultix keeps its own GoRouter,
Riverpod state, backend contract, and feature-based Flutter screens.

## Architecture

- `lib/app.dart`: Material app, theme, and GoRouter route definitions.
- `lib/core/`: backend API, cryptography, encrypted persistence, repositories,
  dependency injection, and synchronization.
- `lib/core/theme/`: shared Material 3 design tokens and
  component themes.
- `lib/core/widgets/`: shared app-level presentation widgets.
- `lib/features/`: feature screens and auth lifecycle controllers.

## Run

Install Flutter dependencies and run the app:

```sh
flutter pub get
flutter run
```

Configure the backend address with `--dart-define=API_BASE_URL=...` when it
differs from the Android emulator default:

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Use HTTPS for non-local deployments.

For local development, copy `.env.example` to `.env`, set `API_BASE_URL`, then
load it into Flutter's compile-time define when running:

```sh
set -a
. ./.env
set +a
flutter run --dart-define="API_BASE_URL=$API_BASE_URL"
```

The real `.env` file is ignored by Git. GitHub Actions builds all supported
native targets (Android, iOS, Linux, macOS, and Windows) on pushes to `main` or
`dev`, pull requests, and version tags. Build outputs are uploaded as workflow
artifacts. Configure the repository variable `API_BASE_URL` under
**Settings → Secrets and variables → Actions → Variables** to embed the
deployment backend URL; the workflow uses the Android emulator default when
the variable is unset. The iOS artifact is unsigned and requires Apple
code-signing credentials before distribution.

Web builds are not included because the app's SQLCipher/FFI storage dependency
requires native platforms.

## Verify

```sh
dart format lib test
flutter analyze
flutter test
```

The backend does not expose MFA or server-backed TOTP endpoints. Authenticator
entries are device-only; the app does not claim zero-knowledge encryption.
