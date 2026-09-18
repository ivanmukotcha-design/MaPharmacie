import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../local_database/local_database.dart';
import '../../../shared/widgets/pf_search_bar.dart';
import '../../../shared/widgets/pf_badge.dart';
import '../../../shared/widgets/barcode_scanner_screen.dart';

// Filtres stock
enum FiltreStock { tous, faible, rupture, expires, expireBientot }

final filtreStockProvider = StateProvider<FiltreStock>(
  (ref) => FiltreStock.tous,
);
final searchStockProvider = StateProvider<String>((ref) => '');

final medicamentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(localChangesProvider);
      final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
      if (pharmacie == null) return [];
      final query = ref.watch(searchStockProvider);
      if (query.isNotEmpty) {
        return LocalDatabase.searchMedicaments(pharmacie.id, query);
      }
      return LocalDatabase.getMedicaments(pharmacie.id);
    });

class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtreActif = ref.watch(filtreStockProvider);
    final medsAsync = ref.watch(medicamentsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Stock médicaments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            onPressed: () async {
              final code = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
              );
              if (code != null && context.mounted) {
                ref.read(searchStockProvider.notifier).state = code;
              }
            },
            tooltip: 'Scanner code-barres',
          ),
        ],
      ),
      floatingActionButton:
          ref.watch(currentPharmacieProvider).valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/medicament/nouveau'),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Ajouter',
                style: AppTextStyles.label.copyWith(color: Colors.white),
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                PfSearchBar(
                  value: ref.watch(searchStockProvider),
                  hint: 'Rechercher un médicament, code-barres...',
                  onChanged: (v) =>
                      ref.read(searchStockProvider.notifier).state = v,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildFiltres(ref, filtreActif),
              ],
            ),
          ),
          Expanded(
            child: medsAsync.when(
              loading: () => _buildLoading(),
              error: (e, _) =>
                  Center(child: Text('Erreur: $e', style: AppTextStyles.body)),
              data: (meds) {
                final filteredMeds = _filtrerMeds(meds, filtreActif);
                if (filteredMeds.isEmpty) return _buildEmpty(filtreActif);
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    100,
                  ),
                  itemCount: filteredMeds.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _MedicamentCard(med: filteredMeds[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltres(WidgetRef ref, FiltreStock actif) {
    final filtres = [
      (FiltreStock.tous, 'Tous', null),
      (FiltreStock.faible, 'Stock faible', AppColors.warning),
      (FiltreStock.rupture, 'Rupture', AppColors.danger),
      (FiltreStock.expires, 'Expirés', AppColors.danger),
      (FiltreStock.expireBientot, 'Expire bientôt', AppColors.warning),
    ];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: filtres.map((f) {
          final selected = actif == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              label: Text(
                f.$2,
                style: AppTextStyles.caption.copyWith(
                  color: selected
                      ? Colors.white
                      : (f.$3 ?? AppColors.textSecondary),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              selected: selected,
              onSelected: (_) =>
                  ref.read(filtreStockProvider.notifier).state = f.$1,
              backgroundColor: f.$3 != null
                  ? f.$3!.withOpacity(0.08)
                  : AppColors.card,
              selectedColor: f.$3 ?? AppColors.primary,
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: f.$3 != null ? f.$3!.withOpacity(0.3) : AppColors.border,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _filtrerMeds(
    List<Map<String, dynamic>> meds,
    FiltreStock filtre,
  ) {
    final now = DateTime.now();
    final dans30j = now.add(const Duration(days: 30));

    return meds.where((m) {
      final totalBase =
          (m['cartons'] as int) *
              (m['cartons_par_boite'] as int) *
              (m['boites_par_plaquette'] as int) *
              (m['plaquettes_par_comprime'] as int) +
          (m['boites'] as int) *
              (m['boites_par_plaquette'] as int) *
              (m['plaquettes_par_comprime'] as int) +
          (m['plaquettes'] as int) * (m['plaquettes_par_comprime'] as int) +
          (m['comprimes'] as int) +
          (m['flacons'] as int);
      final totalBoites = m['unite_prix'] == 'flacon'
          ? m['flacons'] as int
          : (m['cartons'] as int) * (m['cartons_par_boite'] as int) +
                (m['boites'] as int);
      final seuil = m['seuil_alerte'] as int;
      final dateExpStr = m['date_expiration'] as String?;
      DateTime? dateExp = dateExpStr != null
          ? DateTime.tryParse(dateExpStr)
          : null;

      switch (filtre) {
        case FiltreStock.tous:
          return true;
        case FiltreStock.faible:
          return totalBase > 0 && totalBoites <= seuil;
        case FiltreStock.rupture:
          return totalBase == 0;
        case FiltreStock.expires:
          return dateExp != null && dateExp.isBefore(now);
        case FiltreStock.expireBientot:
          return dateExp != null &&
              dateExp.isAfter(now) &&
              dateExp.isBefore(dans30j);
      }
    }).toList();
  }

  Widget _buildLoading() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, __) => Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.border.withOpacity(0.3),
          borderRadius: AppBorderRadius.md,
        ),
      ),
    );
  }

  Widget _buildEmpty(FiltreStock filtre) {
    final msgs = {
      FiltreStock.tous: (
        'Aucun médicament',
        'Ajoutez votre premier médicament en cliquant sur le bouton +',
      ),
      FiltreStock.faible: (
        'Stock suffisant',
        'Aucun médicament n\'est sous le seuil d\'alerte',
      ),
      FiltreStock.rupture: (
        'Pas de rupture',
        'Tous vos médicaments sont en stock',
      ),
      FiltreStock.expires: (
        'Aucun produit expiré',
        'Tous vos médicaments sont dans leur période de validité',
      ),
      FiltreStock.expireBientot: (
        'Aucune expiration proche',
        'Aucun médicament n\'expire dans les 30 prochains jours',
      ),
    };
    final (titre, msg) = msgs[filtre]!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medication_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(titre, style: AppTextStyles.h4, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              msg,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicamentCard extends StatelessWidget {
  final Map<String, dynamic> med;

  const _MedicamentCard({required this.med});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
    final totalBoites = med['unite_prix'] == 'flacon'
        ? med['flacons'] as int
        : (med['cartons'] as int) * (med['cartons_par_boite'] as int) +
              (med['boites'] as int);
    final seuil = med['seuil_alerte'] as int;
    final dateExpStr = med['date_expiration'] as String?;
    final dateExp = dateExpStr != null ? DateTime.tryParse(dateExpStr) : null;

    Color indicateur;
    String statutLabel;
    if (totalBase == 0) {
      indicateur = AppColors.danger;
      statutLabel = 'Rupture';
    } else if (totalBoites <= seuil) {
      indicateur = AppColors.warning;
      statutLabel = 'Stock faible';
    } else {
      indicateur = AppColors.success;
      statutLabel = 'En stock';
    }

    bool expire = dateExp != null && dateExp.isBefore(now);
    bool expireBientot =
        dateExp != null && !expire && dateExp.difference(now).inDays <= 30;

    return GestureDetector(
      onTap: () => context.push('/medicament/${med['id']}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppBorderRadius.md,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Indicateur couleur
            Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: indicateur,
                borderRadius: AppBorderRadius.sm,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Image / icône
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: AppBorderRadius.md,
              ),
              child: med['image_url'] != null
                  ? ClipRRect(
                      borderRadius: AppBorderRadius.md,
                      child: Image.network(
                        med['image_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.medication_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.medication_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          med['nom'] ?? '',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      PfBadge(label: statutLabel, color: indicateur),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    med['categorie'] ?? '',
                    style: AppTextStyles.small.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _stockChip(
                        med['unite_prix'] == 'flacon'
                            ? '${med['flacons']} flacons'
                            : '${med['cartons']}c ${med['boites']}b ${med['plaquettes']}p ${med['comprimes']} cp',
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (expire)
                        _tagChip('Expiré', AppColors.danger)
                      else if (expireBientot)
                        _tagChip(
                          '${dateExp.difference(now).inDays}j',
                          AppColors.warning,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(med['prix_detail'] as num).toStringAsFixed(0)} FC',
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppBorderRadius.sm,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _tagChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: AppBorderRadius.sm,
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
