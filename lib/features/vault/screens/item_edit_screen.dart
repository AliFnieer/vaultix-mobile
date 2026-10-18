import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/secret_repository.dart';
import '../../../core/db/database.dart';
import '../../../core/di/providers.dart';
import '../../auth/controllers/auth_controller.dart';
import 'vault_home_screen.dart';

class ItemEditScreen extends ConsumerStatefulWidget {
  final String? secretId;

  const ItemEditScreen({super.key, this.secretId});

  @override
  ConsumerState<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends ConsumerState<ItemEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _type = TextEditingController(text: 'login');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  String? _selectedVaultId;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final id = widget.secretId;
    if (id != null && id.isNotEmpty) {
      Future.microtask(_loadSecret);
    }
  }

  Future<void> _loadSecret() async {
    final db = ref.read(appDbProvider);
    final vaultKey = ref.read(vaultKeyProvider);
    if (db == null || vaultKey == null) return;
    final row = await db.findSecret(widget.secretId!);
    if (!mounted || row == null) return;
    final fields = await SecretRepository(db, vaultKey).openFields(row);
    setState(() {
      _title.text = row.title;
      _type.text = row.type;
      _selectedVaultId = row.vaultId;
      _username.text = fields['username'] ?? '';
      _password.text = fields['password'] ?? '';
      _url.text = fields['url'] ?? '';
    });
  }

  Future<void> _syncNow() async {
    try {
      await ref.read(syncEngineProvider).synchronize();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync failed. Check your connection and try again.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _type.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final db = ref.read(appDbProvider);
    final vaultKey = ref.read(vaultKeyProvider);
    if (db == null || vaultKey == null) return;

    var targetVaultId = _selectedVaultId;
    if (widget.secretId == null || widget.secretId!.isEmpty) {
      final vaults =
          ref.read(vaultsProvider).asData?.value ?? const <VaultRow>[];
      final currentVaultId = ref.read(selectedVaultProvider);
      targetVaultId ??= currentVaultId;
      if (targetVaultId == null ||
          !vaults.any((vault) => vault.id == targetVaultId)) {
        targetVaultId = vaults
            .where((vault) => vault.isDefault)
            .firstOrNull
            ?.id;
        targetVaultId ??= vaults.firstOrNull?.id;
      }
      if (targetVaultId == null) {
        setState(() {
          _saveError =
              'No vault is available yet. Sync your account and try again.';
        });
        return;
      }
    }

    setState(() => _busy = true);
    setState(() => _saveError = null);
    final repo = SecretRepository(db, vaultKey);
    final fields = {
      if (_username.text.trim().isNotEmpty) 'username': _username.text.trim(),
      if (_password.text.trim().isNotEmpty) 'password': _password.text.trim(),
      if (_url.text.trim().isNotEmpty) 'url': _url.text.trim(),
    };

    try {
      if (widget.secretId != null && widget.secretId!.isNotEmpty) {
        final row = await db.findSecret(widget.secretId!);
        if (row != null) {
          await repo.updateLocal(
            row,
            title: _title.text.trim(),
            type: _type.text.trim().isEmpty ? 'login' : _type.text.trim(),
            vaultId: targetVaultId ?? row.vaultId,
            fields: fields,
          );
        }
      } else {
        await repo.createLocal(
          title: _title.text.trim(),
          type: _type.text.trim().isEmpty ? 'login' : _type.text.trim(),
          vaultId: targetVaultId!,
          fields: fields,
        );
      }
      if (!mounted) return;
      context.go('/vault');
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveError = 'Could not save this item. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.secretId != null && widget.secretId!.isNotEmpty;
    final vaultsState = ref.watch(vaultsProvider);
    final availableVaults = vaultsState.asData?.value ?? const <VaultRow>[];
    final selectedVaultId =
        _selectedVaultId ??
        ref.watch(selectedVaultProvider) ??
        availableVaults.where((vault) => vault.isDefault).firstOrNull?.id ??
        availableVaults.firstOrNull?.id;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit item' : 'New item')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              if (!editing && vaultsState.isLoading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (!editing && vaultsState.hasError) ...[
                const SizedBox(height: 16),
                _VaultNotice(
                  message: 'Could not load your vaults.',
                  actionLabel: 'Try syncing again',
                  onPressed: _syncNow,
                ),
              ],
              if (!editing &&
                  !vaultsState.isLoading &&
                  !vaultsState.hasError &&
                  availableVaults.isEmpty) ...[
                const SizedBox(height: 16),
                _VaultNotice(
                  message: 'Sync your account before adding items.',
                  actionLabel: 'Sync now',
                  onPressed: _syncNow,
                ),
              ],
              const SizedBox(height: 16),
              if (!editing)
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedVaultId),
                  initialValue: selectedVaultId,
                  decoration: const InputDecoration(
                    labelText: 'Save to vault',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  items: [
                    for (final vault in availableVaults)
                      DropdownMenuItem(
                        value: vault.id,
                        child: Text(vault.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedVaultId = value),
                  validator: (value) => value == null
                      ? 'Sync your vault before adding items'
                      : null,
                ),
              if (!editing) const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _type.text.isNotEmpty ? _type.text : 'login',
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'login', child: Text('Login')),
                  DropdownMenuItem(value: 'note', child: Text('Note')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'api_key', child: Text('API key')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _type.text = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
              const SizedBox(height: 24),
              if (_saveError != null) ...[
                Text(
                  _saveError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_busy ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultNotice extends StatelessWidget {
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  const _VaultNotice({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
