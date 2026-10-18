import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' as legacy;
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/di/providers.dart';
import '../../auth/controllers/auth_controller.dart';

final selectedVaultProvider = legacy.StateProvider<String?>((_) => null);
final searchProvider = legacy.StateProvider<String>((_) => '');

final vaultsProvider = StreamProvider<List<VaultRow>>((ref) {
  final db = ref.watch(appDbProvider);
  if (db == null) return const Stream.empty();
  return db.watchVaults();
});

final secretsProvider = StreamProvider<List<SecretRow>>((ref) {
  final db = ref.watch(appDbProvider);
  if (db == null) return const Stream.empty();
  final vaultId = ref.watch(selectedVaultProvider);
  return db.watchSecrets(vaultId: vaultId);
});

class VaultHomeScreen extends ConsumerWidget {
  const VaultHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secrets = ref.watch(secretsProvider);
    final vaults = ref.watch(vaultsProvider);
    final selectedVault = ref.watch(selectedVaultProvider);
    final search = ref.watch(searchProvider).toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vaultix'),
        actions: [
          IconButton(
            tooltip: 'Authenticator',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => context.go('/totp'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/vault/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your passwords, all in one place.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search your vault',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => ref.read(searchProvider.notifier).state = v,
                ),
              ],
            ),
          ),
          vaults.when(
            data: (rows) => SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: selectedVault == null,
                    onSelected: (_) =>
                        ref.read(selectedVaultProvider.notifier).state = null,
                  ),
                  const SizedBox(width: 8),
                  for (final v in rows) ...[
                    ChoiceChip(
                      label: Text(v.name),
                      selected: selectedVault == v.id,
                      onSelected: (_) =>
                          ref.read(selectedVaultProvider.notifier).state = v.id,
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            loading: () => const SizedBox(height: 56),
            error: (error, _) => SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  'Could not load vaults. Pull down to try again.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
          Expanded(
            child: secrets.when(
              data: (rows) {
                final filtered = rows
                    .where((r) => r.title.toLowerCase().contains(search))
                    .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 40,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                search.isEmpty
                                    ? 'Your vault is ready'
                                    : 'No matching items',
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                search.isEmpty
                                    ? 'Add a login, secure note, or card to get started.'
                                    : 'Try a different search term.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              if (search.isEmpty) ...[
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () => context.go('/vault/new'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add your first item'),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(syncEngineProvider)
                                          .synchronize();
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Sync failed. Check your connection and try again.',
                                                ),
                                              ),
                                            );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.sync),
                                  label: const Text('Sync from account'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(syncEngineProvider).synchronize(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final row = filtered[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconFor(row.type),
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                          ),
                          title: Text(
                            row.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            row.type.replaceAll('_', ' '),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          trailing: row.favorite
                              ? Icon(
                                  Icons.star_rounded,
                                  color: Theme.of(context).colorScheme.tertiary,
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => context.go('/vault/item/${row.id}'),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load your items.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(syncEngineProvider).synchronize(),
                      icon: const Icon(Icons.sync),
                      label: const Text('Try syncing again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) context.go('/totp');
          if (i == 2) context.go('/settings');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.vpn_key_outlined),
            label: 'Vault',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            label: 'Codes',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
    'note' => Icons.description_outlined,
    'card' => Icons.credit_card_outlined,
    'api_key' => Icons.key_outlined,
    _ => Icons.language_outlined,
  };
}

/// Shared copy-to-clipboard helper with confirmation.
void copyWithFeedback(BuildContext context, String label, String value) {
  Clipboard.setData(ClipboardData(text: value));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$label copied'),
      duration: const Duration(seconds: 2),
    ),
  );
}
