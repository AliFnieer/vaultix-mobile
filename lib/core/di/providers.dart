import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' as legacy;

import '../api/api_client.dart';
import '../api/auth_api.dart';
import '../api/vault_api.dart';
import '../config/app_config.dart';
import '../crypto/key_store.dart';
import '../crypto/local_key.dart';
import '../db/database.dart';

// ---------------------------------------------------------------------------
// Core providers. Tests override these with in-memory fakes.
// ---------------------------------------------------------------------------

final appConfigProvider = Provider<AppConfig>((_) => AppConfig.fromEnvironment);

/// Platform secure storage (override in tests with an in-memory fake).
final secureStoreProvider = Provider<SecureStore>(
  (_) => const FlutterSecureStore(),
);

final keyStoreProvider = Provider<KeyStore>((_) => const KeyStore());

final localKdfProvider = Provider<LocalKdf>((_) => const Pbkdf2Sha256Kdf());

final tokenStoreProvider = Provider<TokenStore>((ref) {
  final store = ref.watch(secureStoreProvider);
  return TokenStore(_StoreTokenPersistence(store));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
    tokens: ref.watch(tokenStoreProvider),
  );
});

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final vaultApiProvider = Provider<VaultApi>(
  (ref) => VaultApi(ref.watch(apiClientProvider)),
);

/// The open encrypted database; null while locked/logged out.
final appDbProvider = legacy.StateProvider<AppDb?>((_) => null);

/// The unlocked vault key; null while locked/logged out. Never persisted
/// unwrapped except behind the biometric gate.
final vaultKeyProvider = legacy.StateProvider<SecretKey?>((_) => null);

class _StoreTokenPersistence implements TokenPersistence {
  final SecureStore _store;

  _StoreTokenPersistence(this._store);

  @override
  Future<String?> readRefresh() => _store.read('vaultix.session.refresh');

  @override
  Future<void> saveRefresh(String token) =>
      _store.write('vaultix.session.refresh', token);

  @override
  Future<void> clearRefresh() => _store.delete('vaultix.session.refresh');
}
