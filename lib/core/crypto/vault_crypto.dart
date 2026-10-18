import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Client-side vault cryptography.
///
/// KEY HIERARCHY (device protection layer; see docs/security-review.md — the
/// backend itself is NOT zero-knowledge):
///
///   localMaster = PBKDF2(master password, device salt)   // never leaves device
///   wrapKey     = HKDF(localMaster, "vaultix/wrap/v1")   // wraps the random vault key
///   vaultKey    = random 32B                              // encrypts ALL local content
///   dbKey       = HKDF(vaultKey, "vaultix/db/v1")         // SQLCipher passphrase
///
/// AEAD: AES-256-GCM. Blob layout: nonce(12) || ciphertext || mac(16).
///
/// AAD BINDING: every blob is bound to its entity id so ciphertexts cannot be
/// swapped between rows (`secret:<id>`, `totp:<id>`).
class VaultCrypto {
  VaultCrypto._();

  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SecretKey> deriveWrapKey(SecretKey localMaster) =>
      _hkdfKey(localMaster, 'vaultix/wrap/v1');

  static Future<SecretKey> deriveDbKey(SecretKey vaultKey) =>
      _hkdfKey(vaultKey, 'vaultix/db/v1');

  static Future<SecretKey> _hkdfKey(SecretKey ikm, String info) {
    return _hkdf.deriveKey(secretKey: ikm, info: utf8.encode(info));
  }

  // -- AEAD -----------------------------------------------------------------

  /// Encrypts and returns the packed blob (nonce||ct||mac) as base64.
  static Future<String> sealToB64(
    SecretKey key,
    List<int> plaintext, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(plaintext, secretKey: key, aad: aad);
    final packed = Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    return base64Encode(packed);
  }

  static Future<Uint8List> openB64(
    SecretKey key,
    String b64, {
    List<int> aad = const [],
  }) async {
    final packed = base64Decode(b64);
    if (packed.length < 12 + 16) {
      throw const FormatException('ciphertext too short');
    }
    final nonce = packed.sublist(0, 12);
    final mac = Mac(packed.sublist(packed.length - 16));
    final ct = packed.sublist(12, packed.length - 16);
    final clear = await _aes.decrypt(
      SecretBox(ct, nonce: nonce, mac: mac),
      secretKey: key,
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }

  // -- key wrapping -----------------------------------------------------------

  /// Wraps the random vault key under HKDF(localMaster, "wrap"). Stored in the
  /// platform keystore/keychain only; the server never sees it.
  static Future<String> wrapVaultKey(
    SecretKey vaultKey, {
    required SecretKey localMaster,
  }) async {
    final wrapKey = await deriveWrapKey(localMaster);
    final bytes = await vaultKey.extractBytes();
    return sealToB64(wrapKey, bytes);
  }

  static Future<SecretKey> unwrapVaultKey(
    String wrappedB64, {
    required SecretKey localMaster,
  }) async {
    final wrapKey = await deriveWrapKey(localMaster);
    final bytes = await openB64(wrapKey, wrappedB64);
    return SecretKey(bytes);
  }

  /// Deterministic SQLCipher passphrase derived from the vault key. Same key
  /// on every unlock, so the local database survives app restarts.
  static Future<String> dbPassphraseHex(SecretKey vaultKey) async {
    final dbKey = await deriveDbKey(vaultKey);
    final bytes = await dbKey.extractBytes();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Convenience: decode a stored base64 key into a [SecretKey].
  static SecretKey secretKeyFromB64(String b64) => SecretKey(base64Decode(b64));

  static Future<String> keyToB64(SecretKey key) async =>
      base64Encode(await key.extractBytes());
}
