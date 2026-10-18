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

## Verify

```sh
dart format lib test
flutter analyze
flutter test
```

The backend does not expose MFA or server-backed TOTP endpoints. Authenticator
entries are device-only; the app does not claim zero-knowledge encryption.
