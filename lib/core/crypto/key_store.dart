import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Persistent session secrets backed by the platform keystore/keychain.
///
/// Stored here: the server refresh token, the device-local KDF params + salt,
/// and the wrapped vault key (never the master password). The unwrapped vault
/// key is held in memory only while unlocked; when "biometric unlock" is
/// enabled we additionally persist it behind the biometric gate.
class KeyStore {
  const KeyStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _kPrefix = 'vaultix.session';

  String _k(String name) => '$_kPrefix.$name';

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _k('refresh'), value: token);

  Future<String?> readRefreshToken() => _storage.read(key: _k('refresh'));

  Future<void> saveKdfParamsJson(String json) =>
      _storage.write(key: _k('kdf'), value: json);

  Future<String?> readKdfParamsJson() => _storage.read(key: _k('kdf'));

  Future<void> saveWrappedVaultKey(String b64) =>
      _storage.write(key: _k('wrapped_vault_key'), value: b64);

  Future<String?> readWrappedVaultKey() =>
      _storage.read(key: _k('wrapped_vault_key'));

  /// Plaintext vault key for the biometric unlock path. Written ONLY after the
  /// user enables biometric unlock; read ONLY after a successful biometric
  /// prompt (enforced by callers — see AuthController.unlockWithBiometric).
  Future<void> saveBiometricVaultKey(String b64) =>
      _storage.write(key: _k('bio_vault_key'), value: b64);

  Future<String?> readBiometricVaultKey() =>
      _storage.read(key: _k('bio_vault_key'));

  Future<void> clearBiometricVaultKey() =>
      _storage.delete(key: _k('bio_vault_key'));

  Future<void> clearSession() async {
    await _storage.delete(key: _k('refresh'));
    await _storage.delete(key: _k('kdf'));
    await _storage.delete(key: _k('wrapped_vault_key'));
    await _storage.delete(key: _k('bio_vault_key'));
  }

  Future<bool> hasSession() async =>
      (await readRefreshToken())?.isNotEmpty ?? false;

  // -- biometrics -------------------------------------------------------------

  Future<bool> get canUseBiometrics async {
    final la = LocalAuthentication();
    try {
      final can = await la.canCheckBiometrics;
      final supported = await la.isDeviceSupported();
      return can && supported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestBiometricUnlock(String reason) async {
    final la = LocalAuthentication();
    try {
      return await la.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// In-memory session details assembled at login/unlock.
class SessionMaterial {
  final String refreshToken;
  final String wrappedVaultKeyB64;
  final String kdfParamsJson;

  const SessionMaterial({
    required this.refreshToken,
    required this.wrappedVaultKeyB64,
    required this.kdfParamsJson,
  });
}

/// Test seam: abstracts secure storage so unit tests need no platform channel.
abstract class SecureStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  const FlutterSecureStore();

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Decode helper shared by controllers.
String? utf8OrNull(String? s) => s == null || s.isEmpty ? null : s;

Map<String, dynamic>? tryDecodeJson(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
