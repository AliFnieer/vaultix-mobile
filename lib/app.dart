import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/auth/screens/lock_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/totp/screens/scan_qr_screen.dart';
import 'features/totp/screens/totp_list_screen.dart';
import 'features/vault/screens/item_detail_screen.dart';
import 'features/vault/screens/item_edit_screen.dart';
import 'features/vault/screens/vault_home_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class VaultixApp extends ConsumerStatefulWidget {
  const VaultixApp({super.key});

  @override
  ConsumerState<VaultixApp> createState() => _VaultixAppState();
}

class _VaultixAppState extends ConsumerState<VaultixApp> {
  late final GoRouter _router = _buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    return MaterialApp.router(
      title: 'Vaultix',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

GoRouter _buildRouter(WidgetRef ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final goingTo = state.matchedLocation;
      switch (auth.phase) {
        case AuthPhase.unknown:
          return null; // splash handled by screen
        case AuthPhase.loggedOut:
          return goingTo.startsWith('/auth') ? null : '/auth/login';
        case AuthPhase.locked:
          return goingTo == '/lock' ? null : '/lock';
        case AuthPhase.unlocked:
          return (goingTo == '/' ||
                  goingTo.startsWith('/auth') ||
                  goingTo == '/lock')
              ? '/vault'
              : null;
      }
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _SplashScreen()),
      GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/auth/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),
      GoRoute(
        path: '/vault',
        builder: (_, _) => const VaultHomeScreen(),
        routes: [
          GoRoute(
            path: 'item/:id',
            builder: (_, state) =>
                ItemDetailScreen(secretId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'item/:id/edit',
            builder: (_, state) =>
                ItemEditScreen(secretId: state.pathParameters['id']!),
          ),
          GoRoute(path: 'new', builder: (_, _) => const ItemEditScreen()),
        ],
      ),
      GoRoute(path: '/totp', builder: (_, _) => const TotpListScreen()),
      GoRoute(path: '/totp/scan', builder: (_, _) => const ScanQrScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
}

/// Bridges auth state changes into GoRouter re-evaluation.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }

  final WidgetRef _ref;
}

class _SplashScreen extends ConsumerWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
