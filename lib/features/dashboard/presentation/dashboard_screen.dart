import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../models/models.dart';
import '../../../repositories/medicament_repository.dart';
import '../../../local_database/local_database.dart';
import '../../../services/sync_service.dart';
import '../../../shared/widgets/sync_banner.dart';

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats?>((
  ref,
) async {
  ref.watch(localChangesProvider);
  final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
  if (pharmacie == null) return null;

  // On récupère les stats de ventes brutes
  final raw = await LocalDatabase.getDashboardStats(pharmacie.id);

  // On utilise le repository pour avoir les modèles de médicaments
  final repo = ref.read(medicamentRepositoryProvider);
  final meds = await repo.getMedicaments(pharmacie.id);

  int stockFaible = 0, enRupture = 0, expires = 0, expireBientot = 0;

  for (final m in meds) {
    if (m.estEnRupture) {
      enRupture++;
    } else if (m.estStockFaible) {
      stockFaible++;
    }

    if (m.estExpire) {
      expires++;
    } else if (m.expireBientot) {
      expireBientot++;
    }
  }

  return DashboardStats(
    totalMedicaments: raw['total_medicaments'] as int? ?? 0,
    stockFaible: stockFaible,
    enRupture: enRupture,
    expires: expires,
    expireBientot: expireBientot,
    ventesJour: (raw['ventes_jour'] as num?)?.toDouble() ?? 0,
    beneficesJour: (raw['benefices_jour'] as num?)?.toDouble() ?? 0,
    ventesCount: raw['ventes_count'] as int? ?? 0,
  );
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmacieAsync = ref.watch(currentPharmacieProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardStatsProvider.future),
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context, ref, pharmacieAsync, isOnline),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SyncBanner(),
                  _buildVentesCard(statsAsync),
                  const SizedBox(height: 16),
                  _buildStockGrid(context, statsAsync),
                  const SizedBox(height: 24),
                  _buildAccesRapide(context),
                  const SizedBox(height: 24),
                  _buildAlertesSection(context, statsAsync),
                  const SizedBox(height: 100),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<PharmacieModel?> pharmacieAsync,
    bool isOnline,
  ) {
    final pharmacie = pharmacieAsync.valueOrNull;
    final greeting = _getGreeting();
    final now = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now());

    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      elevation: 0,
      backgroundColor: AppColors.primary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$greeting ',
                      style: AppTextStyles.body.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pharmacie?.nom ?? 'Ma Pharmacie',
                      style: AppTextStyles.h2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      now,
                      style: AppTextStyles.small.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              _buildConnectionBadge(isOnline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBadge(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: AppTextStyles.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVentesCard(AsyncValue<DashboardStats?> statsAsync) {
    return statsAsync.when(
      loading: () => const _SkeletonCard(height: 120),
      error: (error, _) =>
          Text('Impossible de charger les statistiques : $error'),
      data: (stats) {
        if (stats == null) return const SizedBox();
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0B6E4F), Color(0xFF1A9E73)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ventes du jour',
                      style: AppTextStyles.small.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${NumberFormat.decimalPattern('fr_FR').format(stats.ventesJour)} FC',
                      style: AppTextStyles.h2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${stats.ventesCount} transaction${stats.ventesCount > 1 ? 's' : ''}',
                      style: AppTextStyles.small.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 50, color: Colors.white24),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bénéfices',
                      style: AppTextStyles.small.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${NumberFormat.decimalPattern('fr_FR').format(stats.beneficesJour)} FC',
                      style: AppTextStyles.h3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Aujourd\'hui',
                      style: AppTextStyles.small.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockGrid(
    BuildContext context,
    AsyncValue<DashboardStats?> statsAsync,
  ) {
    return statsAsync.when(
      loading: () => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: List.generate(4, (_) => const _SkeletonCard(height: 80)),
      ),
      error: (_, __) => const SizedBox(),
      data: (stats) {
        if (stats == null) return const SizedBox();
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            _StatCard(
              label: 'Total produits',
              value: '${stats.totalMedicaments}',
              icon: Icons.inventory_2_outlined,
              color: AppColors.primary,
              onTap: () => context.go('/stock'),
            ),
            _StatCard(
              label: 'Stock faible',
              value: '${stats.stockFaible}',
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              onTap: () => context.go('/stock'),
            ),
            _StatCard(
              label: 'En rupture',
              value: '${stats.enRupture}',
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              onTap: () => context.go('/stock'),
            ),
            _StatCard(
              label: 'Expirations',
              value: '${stats.expireBientot}',
              icon: Icons.event_busy_outlined,
              color: Colors.orange,
              onTap: () => context.go('/stock'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAccesRapide(BuildContext context) {
    final actions = [
      _QuickAction(
        'Vendre',
        Icons.add_shopping_cart,
        AppColors.success,
        '/ventes',
      ),
      _QuickAction('Stock', Icons.medication, AppColors.primary, '/stock'),
      _QuickAction(
        'Historique',
        Icons.history,
        AppColors.secondary,
        '/historique-ventes',
      ),
      _QuickAction('Rapports', Icons.analytics, AppColors.warning, '/rapports'),
      _QuickAction('Contacts', Icons.people, AppColors.info, '/fournisseurs'),
      _QuickAction(
        'Réglages',
        Icons.settings,
        AppColors.textMuted,
        '/parametres',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Accès rapide', style: AppTextStyles.h3),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: actions
              .map((a) => _buildQuickActionItem(context, a))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildQuickActionItem(BuildContext context, _QuickAction a) {
    return GestureDetector(
      onTap: () => context.go(a.route),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(a.icon, color: a.color, size: 28),
            const SizedBox(height: 8),
            Text(
              a.label,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertesSection(
    BuildContext context,
    AsyncValue<DashboardStats?> statsAsync,
  ) {
    return statsAsync.when(
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
      data: (stats) {
        if (stats == null) return const SizedBox();
        final alertes = <Widget>[];
        if (stats.enRupture > 0) {
          alertes.add(
            _AlertItem(
              type: 'Rupture critique',
              message: '${stats.enRupture} produit(s) sont indisponibles.',
              color: AppColors.danger,
              icon: Icons.error_rounded,
            ),
          );
        }
        if (stats.expireBientot > 0) {
          alertes.add(
            _AlertItem(
              type: 'Péremption proche',
              message: '${stats.expireBientot} produit(s) expirent ce mois-ci.',
              color: Colors.orange,
              icon: Icons.timer_outlined,
            ),
          );
        }

        if (alertes.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alertes prioritaires', style: AppTextStyles.h3),
            const SizedBox(height: 12),
            ...alertes,
          ],
        );
      },
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const Spacer(),
            Text(
              value,
              style: AppTextStyles.h2.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: AppTextStyles.small.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final String type, message;
  final Color color;
  final IconData icon;

  const _AlertItem({
    required this.type,
    required this.message,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: AppTextStyles.label.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  message,
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;
  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _QuickAction {
  final String label, route;
  final IconData icon;
  final Color color;
  const _QuickAction(this.label, this.icon, this.color, this.route);
}
