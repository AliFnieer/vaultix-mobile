import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/controllers/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'ACCOUNT',
            style: textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer,
                child: const Icon(Icons.person_outline),
              ),
              title: const Text('Signed in as'),
              subtitle: Text(auth.email ?? 'Vaultix account'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'SECURITY',
            style: textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('Appearance'),
                  subtitle: const Text('Follows your device setting'),
                  trailing: const Icon(Icons.check_circle_outline),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Lock vault'),
                  subtitle: const Text('Hide your vault until you unlock it'),
                  onTap: () => ref.read(authControllerProvider.notifier).lock(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: colors.error),
              title: Text('Sign out', style: TextStyle(color: colors.error)),
              subtitle: const Text('Remove this session from this device'),
              onTap: () => ref.read(authControllerProvider.notifier).logout(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Vaultix keeps a device-encrypted copy of your vault. Your account data is also processed by the Vaultix server.',
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
