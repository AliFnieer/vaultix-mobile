import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TotpListScreen extends ConsumerWidget {
  const TotpListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Authenticator')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/totp/scan'),
        tooltip: 'Add code',
        child: const Icon(Icons.add),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No authenticator codes yet. Add one to generate time-based codes.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
