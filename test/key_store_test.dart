import 'package:flutter_test/flutter_test.dart';
import 'package:vaultix_mobile/core/crypto/key_store.dart';

class _MemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

void main() {
  group('KeyStore.clearSession', () {
    test(
      'clears session credentials but preserves the local vault key',
      () async {
        final storage = _MemorySecureStore();
        final keyStore = KeyStore(storage: storage);
        await keyStore.saveRefreshToken('refresh-token');
        await keyStore.saveKdfParamsJson('{"algo":1}');
        await keyStore.saveWrappedVaultKey('wrapped-key');
        await keyStore.saveBiometricVaultKey('biometric-key');

        await keyStore.clearSession();

        expect(await keyStore.readRefreshToken(), isNull);
        expect(await keyStore.readBiometricVaultKey(), isNull);
        expect(await keyStore.readKdfParamsJson(), '{"algo":1}');
        expect(await keyStore.readWrappedVaultKey(), 'wrapped-key');
        expect(await keyStore.hasSession(), isFalse);
      },
    );
  });
}
