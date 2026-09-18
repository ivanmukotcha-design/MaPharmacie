import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../local_database/local_database.dart';

// ─── HISTORIQUE VENTES ────────────────────────────────────────────────────────
class HistoriqueVentesScreen extends ConsumerStatefulWidget {
  const HistoriqueVentesScreen({super.key});
  @override
  ConsumerState<HistoriqueVentesScreen> createState() => _HistoriqueState();
}

class _HistoriqueState extends ConsumerState<HistoriqueVentesScreen> {
  DateTime? _debut;
  DateTime? _fin;

  @override
  Widget build(BuildContext context) {
    ref.watch(localChangesProvider);
    final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return const Scaffold();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Historique des ventes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_outlined),
            onPressed: _filtreDialog,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: LocalDatabase.getVentes(
          pharmacie.id,
          dateDebut: _debut,
          dateFin: _fin,
        ),
        builder: (ctx, snap) {
          if (snap.hasError)
            return Center(child: Text('Erreur de lecture : ${snap.error}'));
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ventes = snap.data ?? [];
          if (ventes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  Text('Aucune vente', style: AppTextStyles.h4),
                  Text(
                    'Les ventes apparaîtront ici',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          // Calcul totaux
          double totalVentes = 0, totalBenefices = 0;
          for (final v in ventes) {
            totalVentes += (v['total_ttc'] as num?)?.toDouble() ?? 0;
            totalBenefices += (v['benefice'] as num?)?.toDouble() ?? 0;
          }

          return Column(
            children: [
              // Résumé
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryItem(
                        'Ventes totales',
                        '${totalVentes.toStringAsFixed(0)} FC',
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    Expanded(
                      child: _summaryItem(
                        'Bénéfices',
                        '${totalBenefices.toStringAsFixed(0)} FC',
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    Expanded(
                      child: _summaryItem('Transactions', '${ventes.length}'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: ventes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _VenteRow(vente: ventes[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  void _filtreDialog() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _debut = result.start;
        _fin = result.end;
      });
    }
  }
}

class _VenteRow extends StatelessWidget {
  final Map<String, dynamic> vente;
  const _VenteRow({required this.vente});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(vente['date'] as String? ?? '');
    final isGros = vente['type_vente'] == 'gros';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isGros ? AppColors.secondary : AppColors.primary)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isGros ? Icons.warehouse_outlined : Icons.storefront_outlined,
              color: isGros ? AppColors.secondary : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isGros ? 'Vente Grossiste' : 'Vente Détail',
                  style: AppTextStyles.label,
                ),
                if (date != null)
                  Text(
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${((vente['total_ttc'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} FC',
                style: AppTextStyles.label.copyWith(color: AppColors.primary),
              ),
              Text(
                '+${((vente['benefice'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} FC',
                style: AppTextStyles.caption.copyWith(color: AppColors.success),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
