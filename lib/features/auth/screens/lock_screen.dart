import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../controllers/auth_controller.dart';

/// Shown when a session exists but the local vault is locked. Offers
/// biometric unlock (gates LOCAL KEY ACCESS ONLY) and master-password
/// fallback. Never touches server auth.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _bioAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBio();
  }

  Future<void> _checkBio() async {
    final enabled = await ref.read(keyStoreProvider).readBiometricVaultKey();
    final can = await ref.read(keyStoreProvider).canUseBiometrics;
    if (mounted) {
      setState(() => _bioAvailable = can && (enabled?.isNotEmpty ?? false));
      if (can && (enabled?.isNotEmpty ?? false)) {
        // Attempt immediately; silent failure falls back to password entry.
        await _tryBiometric();
      }
    }
  }

  Future<void> _tryBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .unlockWithBiometric();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Biometric unlock failed. Use your master password.';
    });
  }

  Future<void> _unlockWithPassword() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .unlockWithPassword(_password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Wrong master password for this device.';
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authControllerProvider).email;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault locked'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 64),
                const SizedBox(height: 16),
                Text(
                  email ?? 'Welcome back',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                if (_bioAvailable)
                  FilledButton.icon(
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock with biometrics'),
                    onPressed: _busy ? null : _tryBiometric,
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Master password',
                  ),
                  onSubmitted: (_) => _unlockWithPassword(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _unlockWithPassword,
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
