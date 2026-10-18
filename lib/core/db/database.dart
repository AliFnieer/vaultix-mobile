import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Local mirror of the server's vault containers. `dirty` marks rows with
/// local changes not yet acknowledged by the server; `deleted` is a local
/// soft-delete until the outbox DELETE is acked (the server hard-deletes).
class VaultRows extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  TextColumn get icon => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local mirror of server secrets. `fieldsCipher` is the client-side
/// AES-256-GCM blob (base64 nonce||ct||mac, AAD `secret:<id>`) of the JSON
/// fields map — device protection, see docs/security-review.md.
class SecretRows extends Table {
  TextColumn get id => text()();
  TextColumn get vaultId => text()();
  TextColumn get title => text()();
  TextColumn get type => text()();
  TextColumn get fieldsCipher => text()();
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isTrashed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Authenticator entries. DEVICE-ONLY: no server endpoint exists, so these
/// rows never enter the outbox.
class TotpRows extends Table {
  TextColumn get id => text()();
  TextColumn get issuer => text().withDefault(const Constant(''))();
  TextColumn get label => text().withDefault(const Constant(''))();

  /// AES-256-GCM blob (base64) of the base32 secret, AAD `totp:<id>`.
  TextColumn get secretCipher => text()();
  TextColumn get algorithm => text().withDefault(const Constant('SHA1'))();
  IntColumn get digits => integer().withDefault(const Constant(6))();
  IntColumn get periodSeconds => integer().withDefault(const Constant(30))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Offline mutation queue flushed by the sync engine. FIFO by [id].
class OutboxRows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()(); // vault | secret
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // create | update | delete | archive | unarchive | trash | restore | favorite
  TextColumn get payload => text().nullable()(); // JSON body for create/update
  DateTimeColumn get createdAt => dateTime()();
}

/// Key/value metadata (e.g. last full-refetch timestamp).
class MetaRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [VaultRows, SecretRows, TotpRows, OutboxRows, MetaRows])
class AppDb extends _$AppDb {
  AppDb(super.executor);

  @override
  int get schemaVersion => 1;

  // -- vaults ----------------------------------------------------------------

  Stream<List<VaultRow>> watchVaults() =>
      (select(vaultRows)
            ..where((t) => t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<VaultRow?> findVault(String id) =>
      (select(vaultRows)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertVault(VaultRowsCompanion entry) =>
      into(vaultRows).insertOnConflictUpdate(entry);

  // -- secrets ----------------------------------------------------------------

  Stream<List<SecretRow>> watchSecrets({
    String? vaultId,
    bool includeArchived = false,
    bool includeTrashed = false,
  }) {
    final q = select(secretRows)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm.desc(t.favorite),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    if (vaultId != null && vaultId.isNotEmpty) {
      q.where((t) => t.vaultId.equals(vaultId));
    }
    if (!includeArchived) q.where((t) => t.isArchived.equals(false));
    if (!includeTrashed) q.where((t) => t.isTrashed.equals(false));
    return q.watch();
  }

  Future<SecretRow?> findSecret(String id) =>
      (select(secretRows)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertSecret(SecretRowsCompanion entry) =>
      into(secretRows).insertOnConflictUpdate(entry);

  // -- totp --------------------------------------------------------------------

  Stream<List<TotpRow>> watchTotpRows() => (select(
    totpRows,
  )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();

  Future<void> upsertTotpRow(TotpRowsCompanion entry) =>
      into(totpRows).insertOnConflictUpdate(entry);

  Future<void> deleteTotpRow(String id) =>
      (delete(totpRows)..where((t) => t.id.equals(id))).go();

  // -- outbox ------------------------------------------------------------------

  Future<int> enqueue({
    required String entity,
    required String entityId,
    required String op,
    String? payload,
  }) => into(outboxRows).insert(
    OutboxRowsCompanion.insert(
      entity: entity,
      entityId: entityId,
      op: op,
      payload: Value(payload),
      createdAt: DateTime.now().toUtc(),
    ),
  );

  Future<List<OutboxRow>> pendingOutbox() =>
      (select(outboxRows)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<bool> hasPendingOps(String entityId) async => (await (select(
    outboxRows,
  )..where((t) => t.entityId.equals(entityId))).get()).isNotEmpty;

  List<String> decodeTags(String encoded) {
    try {
      final dynamic list = jsonDecode(encoded);
      if (list is List) {
        return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> removeOutbox(int id) =>
      (delete(outboxRows)..where((t) => t.id.equals(id))).go();

  /// Rewrites pending ops' entity ids after the server assigns the real
  /// 24-hex id (no client-generated ids on this backend).
  Future<void> remapOutboxEntity(String oldId, String newId) =>
      (update(outboxRows)..where((t) => t.entityId.equals(oldId))).write(
        OutboxRowsCompanion(entityId: Value(newId)),
      );

  // -- meta ----------------------------------------------------------------------

  Future<String?> getMeta(String key) async => (await (select(
    metaRows,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String value) => into(metaRows)
      .insertOnConflictUpdate(MetaRowsCompanion.insert(key: key, value: value));

  // -- lifecycle ------------------------------------------------------------------

  Future<void> wipeAllData() async {
    await delete(vaultRows).go();
    await delete(secretRows).go();
    await delete(totpRows).go();
    await delete(outboxRows).go();
    await delete(metaRows).go();
  }
}

/// Opens the SQLCipher-encrypted vault database on device. The passphrase is
/// derived from the vault key (HKDF), so the file is unreadable without a
/// successful unlock. Unit tests use `AppDb(NativeDatabase.memory())` instead.
Future<AppDb> openAppDb({required String passphrase}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/vaultix.db');
  return AppDb(
    LazyDatabase(() async {
      return NativeDatabase.createInBackground(
        file,
        setup: (db) {
          db.execute("PRAGMA key = '$passphrase'");
          db.execute('SELECT count(*) FROM sqlite_master');
        },
      );
    }),
  );
}
