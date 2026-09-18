import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../local_database/local_database.dart';
import '../../../config/auth_provider.dart';
import '../../../shared/widgets/pf_badge.dart';
import '../../../shared/widgets/pf_snackbar.dart';
import '../../../repositories/medicament_repository.dart';

class MedicamentDetailScreen extends ConsumerWidget {
  final String id;
  const MedicamentDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localChangesProvider);
    final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: pharmacie != null
            ? LocalDatabase.getMedicaments(pharmacie.id)
            : Future.value([]),
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Impossible de charger le médicament : ${snap.error}',
              ),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final meds = snap.data!;
          final med = meds.firstWhere((m) => m['id'] == id, orElse: () => {});

          if (med.isEmpty) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const Center(child: Text('Médicament introuvable')),
            );
          }

          return _buildDetail(context, ref, med, pharmacie);
        },
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> med,
    dynamic pharmacie,
  ) {
    final now = DateTime.now();
    final totalBoites = med['unite_prix'] == 'flacon'
        ? med['flacons'] as int
        : (med['cartons'] as int) * (med['cartons_par_boite'] as int) +
              (med['boites'] as int);
    final seuil = med['seuil_alerte'] as int;
    final totalBase =
        (med['cartons'] as int) *
            (med['cartons_par_boite'] as int) *
            (med['boites_par_plaquette'] as int) *
            (med['plaquettes_par_comprime'] as int) +
        (med['boites'] as int) *
            (med['boites_par_plaquette'] as int) *
            (med['plaquettes_par_comprime'] as int) +
        (med['plaquettes'] as int) * (med['plaquettes_par_comprime'] as int) +
        (med['comprimes'] as int) +
        (med['flacons'] as int);

    Color statutColor;
    String statutLabel;
    if (totalBase == 0) {
      statutColor = AppColors.danger;
      statutLabel = 'En rupture';
    } else if (totalBoites <= seuil) {
      statutColor = AppColors.warning;
      statutLabel = 'Stock faible';
    } else {
      statutColor = AppColors.success;
      statutLabel = 'En stock';
    }

    final dateExpStr = med['date_expiration'] as String?;
    final dateExp = dateExpStr != null ? DateTime.tryParse(dateExpStr) : null;
    final expire = dateExp != null && dateExp.isBefore(now);
    final joursRestants = dateExp != null
        ? dateExp.difference(now).inDays
        : null;

    return CustomScrollView(
      slivers: [
        // Hero header
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 16,
                color: AppColors.textPrimary,
              ),
            ),
            onPressed: () => context.pop(),
          ),
          actions: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              onPressed: () => context.push('/medicament/$id/modifier'),
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppColors.danger,
                ),
              ),
              onPressed: () =>
                  _confirmerSuppression(context, ref, med, pharmacie),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.8),
                    AppColors.primaryLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: med['image_url'] != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.network(
                                med['image_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.medication_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.medication_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      med['nom'] ?? '',
                      style: AppTextStyles.h3.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      med['categorie'] ?? '',
                      style: AppTextStyles.body.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Statut + expiration
              Row(
                children: [
                  PfBadge(label: statutLabel, color: statutColor),
                  const SizedBox(width: 8),
                  if (dateExp != null)
                    PfBadge(
                      label: expire ? 'Expiré' : 'Expire dans $joursRestants j',
                      color:
                          expire ||
                              (joursRestants != null && joursRestants <= 30)
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Tarifs
              _card('Tarifs', [
                _ligneInfo(
                  'Unité des prix',
                  med['unite_prix'] as String? ?? 'boite',
                ),
                _ligneInfo(
                  'Prix d’achat',
                  med['prix_achat'] == null
                      ? 'À renseigner avant toute vente'
                      : '${(med['prix_achat'] as num).toStringAsFixed(2)} FC',
                ),
                _ligneInfo(
                  'Prix détail',
                  '${(med['prix_detail'] as num).toStringAsFixed(2)} FC',
                ),
                if (ref.watch(wholesaleEnabledProvider))
                  _ligneInfo(
                    'Prix de gros',
                    med['prix_grossiste'] == null
                        ? 'Non renseigné'
                        : '${(med['prix_grossiste'] as num).toStringAsFixed(2)} FC',
                  ),
                _ligneInfo('Fournisseur', med['fournisseur_nom'] ?? 'N/A'),
              ]),
              const SizedBox(height: 12),

              // Stock
              _card('Stock actuel', [
                _stockRow('Cartons', med['cartons'] as int),
                _stockRow('Boîtes', med['boites'] as int),
                _stockRow('Plaquettes', med['plaquettes'] as int),
                _stockRow('Comprimés', med['comprimes'] as int),
                _stockRow('Flacons', med['flacons'] as int),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Seuil alerte',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$seuil ${med['unite_prix'] == 'flacon' ? 'flacons' : 'boîtes'}',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 12),

              // Conversion
              _card('Conversion unités', [
                _ligneInfo('1 carton', '${med['cartons_par_boite']} boîtes'),
                _ligneInfo(
                  '1 boîte',
                  '${med['boites_par_plaquette']} plaquettes',
                ),
                _ligneInfo(
                  '1 plaquette',
                  '${med['plaquettes_par_comprime']} comprimés',
                ),
              ]),
              const SizedBox(height: 12),

              // Informations
              if ((med['description'] as String?)?.isNotEmpty == true ||
                  med['code_barres'] != null) ...[
                _card('Informations', [
                  if ((med['description'] as String?)?.isNotEmpty == true)
                    _ligneInfo('Description', med['description']),
                  if (med['code_barres'] != null)
                    _ligneInfo('Code-barres', med['code_barres']),
                  if (dateExp != null)
                    _ligneInfo(
                      'Date expiration',
                      '${dateExp.day.toString().padLeft(2, '0')}/${dateExp.month.toString().padLeft(2, '0')}/${dateExp.year}',
                    ),
                ]),
                const SizedBox(height: 12),
              ],

              // Actions rapides
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.add_shopping_cart_outlined,
                        size: 18,
                      ),
                      label: const Text('Vendre'),
                      onPressed: () => context.go('/ventes'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text('Modifier'),
                      onPressed: () => context.push('/medicament/$id/modifier'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _card(String titre, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: AppTextStyles.h4),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _ligneInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: AppTextStyles.bodyMedium)),
        ],
      ),
    );
  }

  Widget _stockRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: value > 0
                  ? AppColors.success.withOpacity(0.08)
                  : AppColors.border.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$value',
              style: AppTextStyles.label.copyWith(
                color: value > 0 ? AppColors.success : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmerSuppression(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> med,
    dynamic pharmacie,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce médicament ?'),
        content: Text(
          '${med['nom']} sera archivé. Sa restauration nécessite une intervention technique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(medicamentRepositoryProvider)
                    .deleteMedicament(
                      pharmacie.id as String,
                      med['id'] as String,
                    );
                if (context.mounted) {
                  PfSnackbar.success(
                    context,
                    'Médicament archivé sur cet appareil',
                  );
                  context.go('/stock');
                }
              } catch (error) {
                if (context.mounted)
                  PfSnackbar.error(context, error.toString());
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
