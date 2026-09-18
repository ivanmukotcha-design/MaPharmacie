import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/create_account_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/stock/presentation/stock_screen.dart';
import '../features/stock/presentation/medicament_form_screen.dart';
import '../features/stock/presentation/medicament_detail_screen.dart';
import '../features/sales/presentation/vente_screen.dart';
import '../features/sales/presentation/historique_ventes_screen.dart';
import '../features/suppliers/presentation/fournisseurs_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/support/support_screen.dart';
import '../features/settings/settings_screen.dart';
import '../shared/widgets/main_scaffold.dart';
import 'auth_provider.dart';
import 'access_policy.dart';
import '../features/auth/presentation/access_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  ref.onDispose(notifier.dispose);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final pharmacie = ref.read(currentPharmacieProvider);
      final auth = ref.read(authStateProvider);
      return sessionRedirect(
        location: state.matchedLocation,
        loading: auth.isLoading || (user != null && pharmacie.isLoading),
        hasError: auth.hasError || (user != null && pharmacie.hasError),
        userId: user?.uid,
        pharmacie: pharmacie.valueOrNull,
      );
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (_, __) => const CreateAccountScreen(),
      ),
      GoRoute(path: '/configurer', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/acces', builder: (_, __) => const AccessScreen()),
      // Main app - Shell avec bottom nav
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(path: '/stock', builder: (_, __) => const StockScreen()),
          GoRoute(path: '/ventes', builder: (_, __) => const VenteScreen()),
          GoRoute(
            path: '/historique-ventes',
            builder: (_, __) => const HistoriqueVentesScreen(),
          ),
          GoRoute(
            path: '/fournisseurs',
            builder: (_, __) => const FournisseursScreen(),
          ),
          GoRoute(path: '/rapports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
          GoRoute(
            path: '/parametres',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),

      // Médicament detail / form (full screen, no bottom nav)
      GoRoute(
        path: '/medicament/nouveau',
        builder: (_, __) => const MedicamentFormScreen(),
      ),
      GoRoute(
        path: '/medicament/:id',
        builder: (_, state) =>
            MedicamentDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/medicament/:id/modifier',
        builder: (_, state) =>
            MedicamentFormScreen(medicamentId: state.pathParameters['id']),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Page introuvable: ${state.uri}'),
            TextButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Retour au dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

class RouterNotifier extends ChangeNotifier {
  bool _notificationPending = false;
  bool _disposed = false;

  RouterNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => _scheduleRefresh());
    ref.listen(currentPharmacieProvider, (_, __) => _scheduleRefresh());
  }

  void _scheduleRefresh() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
