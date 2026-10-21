import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/app_exception.dart';
import '../../../core/api/auth_api.dart';
import '../../../core/crypto/local_key.dart';
import '../../../core/crypto/vault_crypto.dart';
import '../../../core/db/database.dart';
import '../../../core/di/providers.dart';
import 'sync_facade.dart';

enum AuthPhase { unknown, loggedOut, locked, unlocked }

class AuthState {
  final AuthPhase phase;
  final String? email;
  final String? error;

  const AuthState._(this.phase, {this.email, this.error});

  const AuthState.loggedOut({String? error})
    : this._(AuthPhase.loggedOut, error: error);

  const AuthState.locked({String? email})
    : this._(AuthPhase.locked, email: email);

  const AuthState.unlocked({required String email})
    : this._(AuthPhase.unlocked, email: email);
}

/// Auth lifecycle: session restore -> locked/unlocked; login/register ->
/// unlocked; lock/logout. The master password is used ONLY to derive the
/// local key that unwraps the vault key; the server receives it verbatim
/// (backend contract, docs/mobile-api-contract.md).
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Kick off async session restore without blocking first frame.
    Future.microtask(_restoreSession);
    return const AuthState._(AuthPhase.unknown);
  }

  Future<void> _restoreSession() async {
    final ks = ref.read(keyStoreProvider);
    final tokens = ref.read(tokenStoreProvider);
    await tokens.loadPersisted();
    if (!tokens.hasRefresh) {
      state = const AuthState.loggedOut();
      return;
    }
    try {
      // Force a refresh+me through the API; single-flight handles concurrency.
      final me = await ref.read(authApiProvider).me();
      state = AuthState.locked(email: me.email);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // Definitive rejection: drop the session.
        await ks.clearSession();
        ref.read(tokenStoreProvider).clearCached();
        state = const AuthState.loggedOut();
      } else {
        // Network unreachable: keep stored material, require local unlock.
        state = const AuthState.locked();
      }
    } catch (e) {
      state = const AuthState.locked();
    }
  }

  // ---------------------------------------------------------------------------
  // login / register
  // ---------------------------------------------------------------------------

  Future<void> login(String email, String password) async {
    state = AuthState._(AuthPhase.unknown);
    try {
      final session = await ref
          .read(authApiProvider)
          .login(email: email, password: password);
      await _adoptSession(session, password);
    } on _LocalVaultUnlockException catch (e) {
      state = AuthState.loggedOut(error: e.message);
    } on ApiException catch (e) {
      state = AuthState.loggedOut(error: e.message);
    } catch (e) {
      developer.log('login failed: $e', name: 'auth');
      state = const AuthState.loggedOut(error: 'Login failed. Try again.');
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    state = AuthState._(AuthPhase.unknown);
    try {
      final session = await ref
          .read(authApiProvider)
          .register(
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
          );
      await _adoptSession(session, password);
    } on _LocalVaultUnlockException catch (e) {
      state = AuthState.loggedOut(error: e.message);
    } on ApiException catch (e) {
      state = AuthState.loggedOut(error: e.message);
    } catch (e) {
      developer.log('register failed: $e', name: 'auth');
      state = const AuthState.loggedOut(error: 'Registration failed.');
    }
  }

  /// Persists tokens + device-local KDF material and opens the vault.
  Future<void> _adoptSession(AuthSession session, String password) async {
    final ks = ref.read(keyStoreProvider);

    // Device-local KDF params: generate on first use, reuse thereafter.
    var kdfJson = await ks.readKdfParamsJson();
    if (kdfJson == null || kdfJson.isEmpty) {
      final params = KdfParams.newPbkdf2();
      kdfJson = jsonEncode(params.toJson());
      await ks.saveKdfParamsJson(kdfJson);
    }
    final kdf = KdfParams.fromJson(jsonDecode(kdfJson) as Map<String, dynamic>);
    final localMaster = await ref
        .read(localKdfProvider)
        .deriveLocalMasterKey(password, kdf);

    // First login on this device: create + wrap the vault key. Subsequent
    // logins unwrap the stored one.
    var wrapped = await ks.readWrappedVaultKey();
    late final SecretKey vaultKey;
    if (wrapped == null || wrapped.isEmpty) {
      vaultKey = SecretKey(randomBytes(32));
      wrapped = await VaultCrypto.wrapVaultKey(
        vaultKey,
        localMaster: localMaster,
      );
      await ks.saveWrappedVaultKey(wrapped);
    } else {
      try {
        vaultKey = await VaultCrypto.unwrapVaultKey(
          wrapped,
          localMaster: localMaster,
        );
      } on SecretBoxAuthenticationError {
        throw const _LocalVaultUnlockException(
          'Your account password was accepted, but it does not unlock the '
          'vault data saved on this device. Your local key was kept unchanged.',
        );
      }
    }

    await _openVault(vaultKey);
    await ks.saveWrappedVaultKey(wrapped);
    await ks.saveRefreshToken(session.refreshToken);
    ref
        .read(tokenStoreProvider)
        .setTokens(access: session.accessToken, refresh: session.refreshToken);
    state = AuthState.unlocked(email: session.user.email);
  }

  // ---------------------------------------------------------------------------
  // local unlock / lock / logout
  // ---------------------------------------------------------------------------

  /// Unlocks the local vault with the master password (no server call).
  Future<bool> unlockWithPassword(String password) async {
    final ks = ref.read(keyStoreProvider);
    final kdfJson = await ks.readKdfParamsJson();
    final wrapped = await ks.readWrappedVaultKey();
    if (kdfJson == null || wrapped == null) return false;
    try {
      final kdf = KdfParams.fromJson(
        jsonDecode(kdfJson) as Map<String, dynamic>,
      );
      final localMaster = await ref
          .read(localKdfProvider)
          .deriveLocalMasterKey(password, kdf);
      final vaultKey = await VaultCrypto.unwrapVaultKey(
        wrapped,
        localMaster: localMaster,
      );
      await _openVault(vaultKey);
      final email = state.email;
      state = AuthState.unlocked(email: email ?? '');
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    } catch (e, stackTrace) {
      developer.log(
        'local vault unlock failed',
        name: 'auth',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Biometric unlock gates ACCESS TO THE LOCAL KEY ONLY (never server auth).
  /// Requires the user to have enabled biometric unlock while unlocked.
  Future<bool> unlockWithBiometric() async {
    final ks = ref.read(keyStoreProvider);
    final can = await ks.canUseBiometrics;
    if (!can) return false;
    final ok = await ks.requestBiometricUnlock('Unlock your Vaultix vault');
    if (!ok) return false;
    final keyB64 = await ks.readBiometricVaultKey();
    if (keyB64 == null || keyB64.isEmpty) return false;
    final vaultKey = VaultCrypto.secretKeyFromB64(keyB64);
    await _openVault(vaultKey);
    final email = state.email;
    state = AuthState.unlocked(email: email ?? '');
    return true;
  }

  /// Persists the wrapped-with-biometric key. Call while unlocked.
  Future<void> enableBiometricUnlock() async {
    final vaultKey = ref.read(vaultKeyProvider);
    if (vaultKey == null) return;
    final ks = ref.read(keyStoreProvider);
    await ks.saveBiometricVaultKey(await VaultCrypto.keyToB64(vaultKey));
  }

  Future<void> disableBiometricUnlock() async {
    await ref.read(keyStoreProvider).clearBiometricVaultKey();
  }

  Future<void> lock() async {
    await _closeVault();
    final email = state.email;
    state = AuthState.locked(email: email);
  }

  Future<void> logout() async {
    try {
      await ref.read(authApiProvider).logout();
    } catch (_) {
      // Best effort; local logout must always succeed.
    }
    await ref.read(keyStoreProvider).clearSession();
    ref.read(tokenStoreProvider).clearCached();
    await _closeVault();
    state = const AuthState.loggedOut();
  }

  // ---------------------------------------------------------------------------
  // vault lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _openVault(SecretKey vaultKey) async {
    // Close any previous connection before opening a new one.
    ref.read(syncEngineProvider).detach();
    ref.read(vaultKeyProvider.notifier).state = null;
    final old = ref.read(appDbProvider);
    ref.read(appDbProvider.notifier).state = null;
    await old?.close();

    final passphrase = await VaultCrypto.dbPassphraseHex(vaultKey);
    final db = await openAppDb(passphrase: passphrase);
    ref.read(vaultKeyProvider.notifier).state = vaultKey;
    ref.read(appDbProvider.notifier).state = db;

    ref.read(syncEngineProvider).attach(db, vaultKey);
  }

  Future<void> _closeVault() async {
    ref.read(syncEngineProvider).detach();
    ref.read(vaultKeyProvider.notifier).state = null;
    final db = ref.read(appDbProvider);
    ref.read(appDbProvider.notifier).state = null;
    if (db != null) {
      // Wipe plaintext caches: the file stays encrypted, but drop rows so a
      // subsequent unlock re-syncs from the server.
      await db.close();
    }
  }
}

class _LocalVaultUnlockException implements Exception {
  final String message;

  const _LocalVaultUnlockException(this.message);
}

/// Sync engine provider, wired after unlock.
final syncEngineProvider = Provider<SyncEngineFacade>((ref) {
  return SyncEngineFacade(ref);
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
