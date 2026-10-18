import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/models.dart';
import '../crypto/local_key.dart';
import '../db/database.dart';

/// Maps server Vault DTOs <-> local rows, queues outbox ops.
class VaultRepository {
  final AppDb _db;

  VaultRepository(this._db);

  Future<void> upsertFromServer(VaultDto dto) => _db.upsertVault(
    VaultRowsCompanion.insert(
      id: dto.id,
      name: dto.name,
      description: Value(dto.description),
      color: Value(dto.color),
      icon: Value(dto.icon),
      isDefault: Value(dto.isDefault),
      sortOrder: Value(dto.sortOrder),
      createdAt: parseServerTime(dto.createdAt),
      updatedAt: parseServerTime(dto.updatedAt),
      dirty: const Value(false),
      deleted: const Value(false),
    ),
  );

  /// Creates a local row with a client UUID; the sync engine remaps the id
  /// after the server assigns its 24-hex id (backend has no client ids).
  Future<String> createLocal({
    required String name,
    String description = '',
  }) async {
    final id = newClientUuid();
    final now = DateTime.now().toUtc();
    await _db.upsertVault(
      VaultRowsCompanion.insert(
        id: id,
        name: name,
        description: Value(description),
        createdAt: now,
        updatedAt: now,
        dirty: const Value(true),
      ),
    );
    await _db.enqueue(
      entity: 'vault',
      entityId: id,
      op: 'create',
      payload: jsonEncode({'name': name, 'description': description}),
    );
    return id;
  }

  Future<void> updateLocal(
    VaultRow row, {
    required String name,
    String description = '',
  }) async {
    final now = DateTime.now().toUtc();
    await _db.upsertVault(
      VaultRowsCompanion(
        id: Value(row.id),
        name: Value(name),
        description: Value(description),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    final body = jsonEncode({'name': name, 'description': description});
    if (isServerId(row.id)) {
      await _db.enqueue(
        entity: 'vault',
        entityId: row.id,
        op: 'update',
        payload: body,
      );
    } else {
      // Not yet pushed: fold into the pending create.
      await replacePendingCreate(_db, row.id, 'vault', body);
    }
  }

  Future<void> deleteLocal(VaultRow row) async {
    if (isServerId(row.id)) {
      await _db.upsertVault(
        VaultRowsCompanion(id: Value(row.id), deleted: const Value(true)),
      );
      await _db.enqueue(entity: 'vault', entityId: row.id, op: 'delete');
    } else {
      // Never pushed: drop row + pending ops entirely.
      await dropPendingOps(_db, row.id);
      await (_db.delete(_db.vaultRows)..where((t) => t.id.equals(row.id))).go();
    }
  }
}

/// Helper used by both repositories: after a create is acknowledged the
/// server returns its real id; re-key the local row and pending ops.
Future<void> remapEntityId(
  AppDb db, {
  required String oldId,
  required String newId,
}) async {
  await db.remapOutboxEntity(oldId, newId);
}

Future<void> replacePendingCreate(
  AppDb db,
  String entityId,
  String entity,
  String body,
) async {
  final ops = await db.pendingOutbox();
  for (final op in ops.where(
    (o) => o.entityId == entityId && o.op == 'create',
  )) {
    await db.removeOutbox(op.id);
  }
  await db.enqueue(
    entity: entity,
    entityId: entityId,
    op: 'create',
    payload: body,
  );
}

Future<void> dropPendingOps(AppDb db, String entityId) async {
  final ops = await db.pendingOutbox();
  for (final op in ops.where((o) => o.entityId == entityId)) {
    await db.removeOutbox(op.id);
  }
}

/// 24-char hex = server ObjectID; anything else is a local client UUID.
bool isServerId(String id) => id.length == 24;

DateTime parseServerTime(String s) {
  if (s.isEmpty) return DateTime.now().toUtc();
  return DateTime.tryParse(s)?.toUtc() ?? DateTime.now().toUtc();
}

String newClientUuid() {
  final r = randomBytes(16);
  r[6] = (r[6] & 0x0f) | 0x40;
  r[8] = (r[8] & 0x3f) | 0x80;
  String hex(int start, int end) => r
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
