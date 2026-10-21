import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../crypto/totp.dart';
import '../crypto/vault_crypto.dart';
import '../db/database.dart';
import 'vault_repository.dart';

class TotpRepository {
  final AppDb _db;
  final SecretKey _vaultKey;

  TotpRepository(this._db, this._vaultKey);

  Future<void> add(TotpConfig config) async {
    if (!config.isValid) {
      throw const FormatException('Invalid TOTP configuration.');
    }
    final id = newClientUuid();
    final secretCipher = await VaultCrypto.sealToB64(
      _vaultKey,
      utf8.encode(config.secretB32),
      aad: utf8.encode('totp:$id'),
    );
    await _db.upsertTotpRow(
      TotpRowsCompanion.insert(
        id: id,
        issuer: Value(config.issuer),
        label: Value(config.account),
        secretCipher: secretCipher,
        algorithm: Value(_algorithmName(config.algorithm)),
        digits: Value(config.digits),
        periodSeconds: Value(config.period),
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<String> openSecret(TotpRow row) async {
    final clear = await VaultCrypto.openB64(
      _vaultKey,
      row.secretCipher,
      aad: utf8.encode('totp:${row.id}'),
    );
    return utf8.decode(clear);
  }

  Future<void> delete(String id) => _db.deleteTotpRow(id);

  static String _algorithmName(TotpAlgorithm algorithm) => switch (algorithm) {
    TotpAlgorithm.sha1 => 'SHA1',
    TotpAlgorithm.sha256 => 'SHA256',
    TotpAlgorithm.sha512 => 'SHA512',
  };
}
