import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/totp_repository.dart';
import '../../../core/di/providers.dart';
import '../../../core/crypto/totp.dart';
import '../../../core/db/database.dart';

final totpRowsProvider = StreamProvider<List<TotpRow>>((ref) {
  final db = ref.watch(appDbProvider);
  if (db == null) return const Stream.empty();
  return db.watchTotpRows();
});

class TotpListScreen extends ConsumerStatefulWidget {
  const TotpListScreen({super.key});

  @override
  ConsumerState<TotpListScreen> createState() => _TotpListScreenState();
}

class _TotpListScreenState extends ConsumerState<TotpListScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(totpRowsProvider);
    final db = ref.watch(appDbProvider);
    final key = ref.watch(vaultKeyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Authenticator')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/totp/scan'),
        tooltip: 'Add code',
        child: const Icon(Icons.add),
      ),
      body: rows.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No authenticator codes yet. Add one to generate '
                  'time-based codes.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (db == null || key == null) {
            return const Center(
              child: Text('Unlock your vault to view codes.'),
            );
          }
          final repository = TotpRepository(db, key);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: items.length,
            itemBuilder: (context, index) => _TotpEntryCard(
              key: ValueKey(items[index].id),
              row: items[index],
              repository: repository,
              now: _now,
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load authenticator codes.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ),
    );
  }
}

class _TotpEntryCard extends StatefulWidget {
  final TotpRow row;
  final TotpRepository repository;
  final DateTime now;

  const _TotpEntryCard({
    super.key,
    required this.row,
    required this.repository,
    required this.now,
  });

  @override
  State<_TotpEntryCard> createState() => _TotpEntryCardState();
}

class _TotpEntryCardState extends State<_TotpEntryCard> {
  late Future<String> _secret;

  @override
  void initState() {
    super.initState();
    _secret = widget.repository.openSecret(widget.row);
  }

  @override
  void didUpdateWidget(covariant _TotpEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.secretCipher != widget.row.secretCipher) {
      _secret = widget.repository.openSecret(widget.row);
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Code copied')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove authenticator code?'),
        content: Text(
          'Remove the code for ${widget.row.issuer.isEmpty ? widget.row.label : widget.row.issuer}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.repository.delete(widget.row.id);
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'Vaultix authenticator',
            context: ErrorDescription('while removing a TOTP code'),
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not remove this code.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final period = row.periodSeconds;
    final remaining = totpRemainingSeconds(widget.now, period: period);
    final progress = remaining / period;
    final algorithm = switch (row.algorithm.toUpperCase()) {
      'SHA256' => TotpAlgorithm.sha256,
      'SHA512' => TotpAlgorithm.sha512,
      _ => TotpAlgorithm.sha1,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<String>(
        future: _secret,
        builder: (context, snapshot) {
          final secret = snapshot.data;
          String? code;
          if (secret != null) {
            try {
              code = totpCode(
                secretB32: secret,
                time: widget.now,
                algorithm: algorithm,
                digits: row.digits,
                period: period,
              );
            } on FormatException {
              code = null;
            }
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.issuer.isEmpty ? row.label : row.issuer,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (row.issuer.isNotEmpty && row.label.isNotEmpty)
                            Text(
                              row.label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove code',
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snapshot.hasError)
                  Text(
                    'Could not decrypt this code.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else if (code == null)
                  const Text('Invalid authenticator setup data.')
                else
                  InkWell(
                    onTap: () => _copyCode(code!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _formatCode(code, row.digits),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              letterSpacing: 3,
                            ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${remaining}s'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatCode(String code, int digits) {
    if (digits == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    return code;
  }
}
