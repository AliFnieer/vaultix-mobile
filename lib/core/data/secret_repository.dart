import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../api/models.dart';
import '../crypto/vault_crypto.dart';
import '../db/database.dart';
import 'vault_repository.dart';

/// Secrets repository: server sync + client-side field encryption.
///
/// Local fields are sealed with AES-256-GCM under the vault key, AAD
/// `secret:<id>` — ciphertexts cannot be swapped between rows.
class SecretRepository {
  final AppDb _db;
  final SecretKey _vaultKey;

  SecretRepository(this._db, this._vaultKey);

  Future<String> _sealFields(String id, Map<String, String> fields) =>
      VaultCrypto.sealToB64(
        _vaultKey,
        utf8.encode(jsonEncode(fields)),
        aad: utf8.encode('secret:$id'),
      );

  /// Decrypts the stored fields of a local row (UI reads).
  Future<Map<String, String>> openFields(SecretRow row) async {
    final clear = await VaultCrypto.openB64(
      _vaultKey,
      row.fieldsCipher,
      aad: utf8.encode('secret:${row.id}'),
    );
    final decoded = jsonDecode(utf8.decode(clear));
    return ((decoded as Map?) ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
    );
  }

  Future<void> upsertFromServer(SecretDto dto) async {
    final cipher = await _sealFields(dto.id, dto.fields);
    await _db.upsertSecret(
      SecretRowsCompanion.insert(
        id: dto.id,
        vaultId: dto.vaultId,
        title: dto.title,
        type: dto.type,
        fieldsCipher: cipher,
        tags: Value(jsonEncode(dto.tags)),
        favorite: Value(dto.favorite),
        isArchived: Value(dto.isArchived),
        isTrashed: Value(dto.isTrashed),
        createdAt: parseServerTime(dto.createdAt),
        updatedAt: parseServerTime(dto.updatedAt),
        dirty: const Value(false),
        deleted: const Value(false),
      ),
    );
  }

  Future<String> createLocal({
    required String title,
    required String type,
    required String vaultId,
    required Map<String, String> fields,
    List<String> tags = const [],
    bool favorite = false,
  }) async {
    final id = newClientUuid();
    final cipher = await _sealFields(id, fields);
    final now = DateTime.now().toUtc();
    await _db.upsertSecret(
      SecretRowsCompanion.insert(
        id: id,
        vaultId: vaultId,
        title: title,
        type: type,
        fieldsCipher: cipher,
        tags: Value(jsonEncode(tags)),
        favorite: Value(favorite),
        createdAt: now,
        updatedAt: now,
        dirty: const Value(true),
      ),
    );
    await _db.enqueue(
      entity: 'secret',
      entityId: id,
      op: 'create',
      payload: jsonEncode({
        'title': title,
        'type': type,
        'vault_id': vaultId,
        'fields': fields,
        'tags': tags,
        'favorite': favorite,
      }),
    );
    return id;
  }

  Future<void> updateLocal(
    SecretRow row, {
    required String title,
    required String type,
    required String vaultId,
    required Map<String, String> fields,
    List<String> tags = const [],
    bool favorite = false,
  }) async {
    final cipher = await _sealFields(row.id, fields);
    final now = DateTime.now().toUtc();
    await _db.upsertSecret(
      SecretRowsCompanion(
        id: Value(row.id),
        vaultId: Value(vaultId),
        title: Value(title),
        type: Value(type),
        fieldsCipher: Value(cipher),
        tags: Value(jsonEncode(tags)),
        favorite: Value(favorite),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    final body = jsonEncode({
      'title': title,
      'type': type,
      'vault_id': vaultId,
      'fields': fields,
      'tags': tags,
      'favorite': favorite,
    });
    if (isServerId(row.id)) {
      await _db.enqueue(
        entity: 'secret',
        entityId: row.id,
        op: 'update',
        payload: body,
      );
    } else {
      await replacePendingCreate(_db, row.id, 'secret', body);
    }
  }

  /// archive/trash/restore use the server's flag endpoints; favorite rides on
  /// the full update payload (the server endpoint only toggles).
  Future<void> setFlagLocal(SecretRow row, String flagOp, bool value) async {
    if (flagOp == 'favorite') {
      await _db.upsertSecret(
        SecretRowsCompanion(
          id: Value(row.id),
          favorite: Value(value),
          dirty: const Value(true),
        ),
      );
      if (isServerId(row.id)) {
        await _db.enqueue(
          entity: 'secret',
          entityId: row.id,
          op: 'update',
          payload: null,
        );
      }
      return;
    }
    await _db.upsertSecret(
      SecretRowsCompanion(
        id: Value(row.id),
        isArchived: flagOp == 'archive'
            ? const Value(true)
            : flagOp == 'unarchive'
            ? const Value(false)
            : Value(row.isArchived),
        isTrashed: flagOp == 'trash'
            ? const Value(true)
            : flagOp == 'restore'
            ? const Value(false)
            : Value(row.isTrashed),
        dirty: const Value(true),
      ),
    );
    if (isServerId(row.id)) {
      await _db.enqueue(entity: 'secret', entityId: row.id, op: flagOp);
    }
  }

  Future<void> deleteLocal(SecretRow row) async {
    if (isServerId(row.id)) {
      await _db.upsertSecret(
        SecretRowsCompanion(
          id: Value(row.id),
          deleted: const Value(true),
          dirty: const Value(true),
        ),
      );
      await _db.enqueue(entity: 'secret', entityId: row.id, op: 'delete');
    } else {
      await dropPendingOps(_db, row.id);
      await (_db.delete(
        _db.secretRows,
      )..where((t) => t.id.equals(row.id))).go();
    }
  }
}
