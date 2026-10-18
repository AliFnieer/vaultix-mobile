import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/secret_repository.dart';
import '../../../core/db/database.dart';
import '../../../core/di/providers.dart';
import 'vault_home_screen.dart';

final secretDetailProvider = FutureProvider.family<SecretRow?, String>((
  ref,
  id,
) async {
  final db = ref.watch(appDbProvider);
  if (db == null) return null;
  return db.findSecret(id);
});

class ItemDetailScreen extends ConsumerWidget {
  final String secretId;

  const ItemDetailScreen({super.key, required this.secretId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.watch(secretDetailProvider(secretId));
    final db = ref.watch(appDbProvider);
    final vaultKey = ref.watch(vaultKeyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item'),
        actions: [
          future.maybeWhen(
            data: (row) => row == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: row.favorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    icon: Icon(row.favorite ? Icons.star : Icons.star_border),
                    onPressed: () async {
                      final repo = SecretRepository(db!, vaultKey!);
                      await repo.setFlagLocal(row, 'favorite', !row.favorite);
                    },
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: future.when(
        data: (row) {
          if (row == null) {
            return const Center(child: Text('Item not found'));
          }
          return FutureBuilder<Map<String, String>>(
            future: SecretRepository(db!, vaultKey!).openFields(row),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final fields = snap.data ?? const <String, String>{};
              return ListView(
                children: [
                  ListTile(
                    title: Text(
                      row.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    subtitle: Text(row.type),
                  ),
                  const Divider(),
                  for (final e in fields.entries)
                    ListTile(
                      title: Text(e.key),
                      subtitle: Text(e.value),
                      trailing: IconButton(
                        tooltip: 'Copy ${e.key}',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () =>
                            copyWithFeedback(context, e.key, e.value),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                            onPressed: () =>
                                context.go('/vault/item/$secretId/edit'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                            onPressed: () => _confirmDelete(context, ref, row),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SecretRow row,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${row.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final db = ref.read(appDbProvider);
    final vaultKey = ref.read(vaultKeyProvider);
    if (db == null || vaultKey == null) return;
    await SecretRepository(db, vaultKey).deleteLocal(row);
    if (context.mounted) context.go('/vault');
  }
}
