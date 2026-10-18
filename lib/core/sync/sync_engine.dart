import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../api/app_exception.dart';
import '../api/models.dart';
import '../api/vault_api.dart';
import '../data/secret_repository.dart';
import '../data/vault_repository.dart';
import '../db/database.dart';

/// Offline-first sync engine.
///
/// The backend has NO delta protocol (audit §2), so:
///  - PUSH: FIFO replay of the local outbox against the CRUD endpoints.
///    Creates return server ids; local rows and pending ops are remapped.
///    Network failures keep the op for the next run (no premature ack).
///  - PULL: full refetch of vaults + secrets (paginated), upsert by id, then
///    delete local rows absent from the server UNLESS they are dirty or use a
///    client UUID (not pushed yet).
///  - CONFLICTS: push-then-pull ordering flushes dirty rows first; the server
///    has no OCC/version field so remote edits made during our push window are
///    LWW-lost (backend limitation). Permanent rejections (409/400/dupe-500)
///    drop the op and surface [onConflict]; network/5xx keeps the op.
class SyncEngine {
  final AppDb _db;
  final VaultApi _api;
  final SecretKey _vaultKey;

  void Function(String message)? onConflict;

  bool _running = false;

  SyncEngine(this._db, this._api, this._vaultKey);

  Future<void> synchronize() async {
    if (_running) return; // coalesce concurrent triggers
    _running = true;
    try {
      await _push();
      await _pull();
      await _db.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
    } finally {
      _running = false;
    }
  }

  // ---------------------------------------------------------------------------
  // PUSH
  // ---------------------------------------------------------------------------

  Future<void> _push() async {
    final vaultRepo = VaultRepository(_db);
    final secretRepo = SecretRepository(_db, _vaultKey);

    for (final op in await _db.pendingOutbox()) {
      try {
        switch ((op.entity, op.op)) {
          case ('vault', 'create'):
            final payload = jsonDecode(op.payload!) as Map<String, dynamic>;
            final dto = await _api.createVault(
              name: payload['name'] as String,
              description: payload['description'] as String? ?? '',
            );
            await vaultRepo.upsertFromServer(dto);
            await _remapVaultRow(op.entityId, dto.id);
            await _db.remapOutboxEntity(op.entityId, dto.id);

          case ('vault', 'update'):
            final payload = jsonDecode(op.payload!) as Map<String, dynamic>;
            final dto = await _api.updateVault(
              id: op.entityId,
              name: payload['name'] as String,
              description: payload['description'] as String? ?? '',
            );
            await vaultRepo.upsertFromServer(dto);

          case ('vault', 'delete'):
            await _api.deleteVault(op.entityId);

          case ('secret', 'create'):
            final payload = jsonDecode(op.payload!) as Map<String, dynamic>;
            final dto = await _api.createSecret(
              title: payload['title'] as String,
              type: payload['type'] as String,
              vaultId: payload['vault_id'] as String,
              fields: _strMap(payload['fields']),
              tags: ((payload['tags'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList(),
              favorite: payload['favorite'] as bool? ?? false,
            );
            await secretRepo.upsertFromServer(dto);
            await _remapSecretRow(op.entityId, dto.id);
            await _db.remapOutboxEntity(op.entityId, dto.id);

          case ('secret', 'update'):
            final row = await _db.findSecret(op.entityId);
            if (row == null) break; // row vanished locally; ack and drop
            final Map<String, dynamic> payload;
            if (op.payload == null) {
              // favorite-only update: rebuild the full body from the row.
              payload = {
                'title': row.title,
                'type': row.type,
                'vault_id': row.vaultId,
                'fields': await secretRepo.openFields(row),
                'tags': _db.decodeTags(row.tags),
                'favorite': row.favorite,
              };
            } else {
              payload = jsonDecode(op.payload!) as Map<String, dynamic>;
            }
            final dto = await _api.updateSecret(
              id: op.entityId,
              title: payload['title'] as String,
              type: payload['type'] as String,
              vaultId: payload['vault_id'] as String,
              fields: _strMap(payload['fields']),
              tags: ((payload['tags'] as List?) ?? const [])
                  .map((e) => e.toString())
                  .toList(),
              favorite: payload['favorite'] as bool? ?? false,
            );
            await secretRepo.upsertFromServer(dto);

          case ('secret', 'delete'):
            await _api.deleteSecret(op.entityId);

          case ('secret', String flag)
              when const {
                'archive',
                'unarchive',
                'trash',
                'restore',
              }.contains(flag):
            await _api.secretFlag(op.entityId, flag);

          default:
            developer.log(
              'sync: unknown outbox op ${op.entity}/${op.op}, dropping',
              name: 'sync',
            );
        }
        await _db.removeOutbox(op.id);
      } on ApiException catch (e) {
        if (e.isNotFound) {
          // Already deleted server-side (or never existed): ack and move on.
          await _db.removeOutbox(op.id);
          continue;
        }
        if (e.isConflict || e.isValidation || e.maybeDuplicateTitle) {
          // Permanent rejection: drop the op, surface it, keep going.
          onConflict?.call(e.message);
          developer.log(
            'sync: dropping rejected op ${op.entity}/${op.op}: ${e.message}',
            name: 'sync',
          );
          await _db.removeOutbox(op.id);
          continue;
        }
        rethrow; // network/5xx (non-dupe): keep the op, retry next sync
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ID REMAPPING (backend assigns ids; local rows start as client UUIDs)
  // ---------------------------------------------------------------------------

  Future<void> _remapVaultRow(String oldId, String newId) async {
    final row = await _db.findVault(oldId);
    if (row != null) {
      await _db.upsertVault(
        VaultRowsCompanion(
          id: Value(newId),
          name: Value(row.name),
          description: Value(row.description),
          color: Value(row.color),
          icon: Value(row.icon),
          isDefault: Value(row.isDefault),
          sortOrder: Value(row.sortOrder),
          createdAt: Value(row.createdAt),
          updatedAt: Value(row.updatedAt),
          dirty: const Value(false),
          deleted: Value(row.deleted),
        ),
      );
      await (_db.delete(_db.vaultRows)..where((t) => t.id.equals(oldId))).go();
    }
    // Secrets created offline against this vault must point at the new id.
    final affected = await (_db.select(
      _db.secretRows,
    )..where((t) => t.vaultId.equals(oldId))).get();
    for (final s in affected) {
      await _db.upsertSecret(
        SecretRowsCompanion(id: Value(s.id), vaultId: Value(newId)),
      );
      final ops = await _db.pendingOutbox();
      for (final op in ops.where((o) => o.entityId == s.id)) {
        final payload = op.payload?.replaceAll(oldId, newId);
        await _db.removeOutbox(op.id);
        await _db.enqueue(
          entity: op.entity,
          entityId: op.entityId,
          op: op.op,
          payload: payload,
        );
      }
    }
  }

  Future<void> _remapSecretRow(String oldId, String newId) async {
    final row = await _db.findSecret(oldId);
    if (row == null) return;
    // Re-seal the fields under the new id's AAD binding.
    final repo = SecretRepository(_db, _vaultKey);
    final clearFields = await repo.openFields(row);
    await repo.upsertFromServer(
      SecretDto(
        id: newId,
        vaultId: row.vaultId,
        title: row.title,
        type: row.type,
        fields: clearFields,
        tags: _db.decodeTags(row.tags),
        favorite: row.favorite,
        isArchived: row.isArchived,
        isTrashed: row.isTrashed,
        createdAt: row.createdAt.toIso8601String(),
        updatedAt: row.updatedAt.toIso8601String(),
      ),
    );
    await (_db.delete(_db.secretRows)..where((t) => t.id.equals(oldId))).go();
  }

  // ---------------------------------------------------------------------------
  // PULL (full refetch — the only protocol this backend offers)
  // ---------------------------------------------------------------------------

  Future<void> _pull() async {
    final vaultRepo = VaultRepository(_db);
    final secretRepo = SecretRepository(_db, _vaultKey);

    // Vaults: single list call (backend does not paginate vaults).
    final vaults = await _api.listVaults();
    final seenVaultIds = <String>{};
    for (final v in vaults) {
      seenVaultIds.add(v.id);
      await vaultRepo.upsertFromServer(v);
    }
    final localVaults = await _db.select(_db.vaultRows).get();
    for (final row in localVaults) {
      // Skip dirty rows (pending local edits) and client-UUID rows (not
      // pushed yet) — no premature deletion of unacknowledged data.
      if (row.deleted || row.dirty || !isServerId(row.id)) continue;
      if (!seenVaultIds.contains(row.id)) {
        await (_db.delete(
          _db.vaultRows,
        )..where((t) => t.id.equals(row.id))).go();
      }
    }

    // Secrets: paginate until a short page.
    final seenSecretIds = <String>{};
    var page = 1;
    while (true) {
      final resp = await _api.listSecrets(page: page, limit: 100);
      for (final s in resp.secrets) {
        seenSecretIds.add(s.id);
        await secretRepo.upsertFromServer(s);
      }
      if (resp.secrets.isEmpty || resp.secrets.length < resp.limit) break;
      page = resp.page + 1;
    }
    final localSecrets = await _db.select(_db.secretRows).get();
    for (final row in localSecrets) {
      if (row.deleted || row.dirty || !isServerId(row.id)) continue;
      if (!seenSecretIds.contains(row.id)) {
        await (_db.delete(
          _db.secretRows,
        )..where((t) => t.id.equals(row.id))).go();
      }
    }
  }

  Map<String, String> _strMap(Object? m) => ((m as Map?) ?? const {}).map(
    (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
  );
}
