import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/login_screen.dart';
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
import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/admin/presentation/admin_pharmacies_screen.dart';
import '../features/admin/presentation/admin_tarifs_screen.dart';
import '../shared/widgets/main_scaffold.dart';
import '../core/constants/app_constants.dart';
import 'auth_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
      
      final authLoading = ref.read(authStateProvider).isLoading;
      final pharmaLoading = ref.read(currentPharmacieProvider).isLoading;

      if (state.matchedLocation == '/splash') return null;
      if (authLoading || pharmaLoading) return null;
      
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register');

      if (!isLoggedIn) {
        return isAuthRoute ? null : '/login';
      }

      if (isAuthRoute) return '/dashboard';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

      // Main app - Shell avec bottom nav
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/stock', builder: (_, __) => const StockScreen()),
          GoRoute(path: '/ventes', builder: (_, __) => const VenteScreen()),
          GoRoute(
            path: '/historique-ventes',
            builder: (_, __) => const HistoriqueVentesScreen(),
          ),
          GoRoute(path: '/fournisseurs', builder: (_, __) => const FournisseursScreen()),
          GoRoute(path: '/rapports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
          GoRoute(path: '/parametres', builder: (_, __) => const SettingsScreen()),
        ],
      ),

      // Médicament detail / form (full screen, no bottom nav)
      GoRoute(
        path: '/medicament/nouveau',
        builder: (_, __) => const MedicamentFormScreen(),
      ),
      GoRoute(
        path: '/medicament/:id',
        builder: (_, state) => MedicamentDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/medicament/:id/modifier',
        builder: (_, state) => MedicamentFormScreen(medicamentId: state.pathParameters['id']),
      ),

      // Admin routes
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/pharmacies', builder: (_, __) => const AdminPharmaciesScreen()),
      GoRoute(path: '/admin/tarifs', builder: (_, __) => const AdminTarifsScreen()),
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
});

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
    _ref.listen(currentPharmacieProvider, (_, __) => notifyListeners());
  }
}
