import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/di/providers.dart';
import '../../../core/sync/sync_engine.dart';

/// Indirection over [SyncEngine] so the app can reference sync before the
/// vault is unlocked (the real engine attaches on unlock with db + key).
class SyncEngineFacade {
  final Ref _ref;

  SyncEngineFacade(this._ref);

  SyncEngine? _engine;

  /// Messages from permanent push rejections, surfaced as snackbars.
  final List<String> conflicts = [];

  void attach(AppDb db, SecretKey vaultKey) {
    _engine = SyncEngine(db, _ref.read(vaultApiProvider), vaultKey)
      ..onConflict = conflicts.add;
  }

  void detach() {
    _engine = null;
  }

  bool get isAttached => _engine != null;

  Future<void> synchronize() async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('Cannot synchronize while the vault is locked.');
    }
    await engine.synchronize();
  }
}
