import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/models.dart';
import '../../../repositories/vente_repository.dart';
import '../../../local_database/local_database.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_search_bar.dart';
import '../../../shared/widgets/pf_snackbar.dart';

/// État temporaire d'un article dans le panier
class PanierItem {
  final MedicamentModel medicament;
  int quantite;
  String unite;
  double prixApplique;

  PanierItem({
    required this.medicament,
    this.quantite = 1,
    this.unite = 'boite',
    required this.prixApplique,
  });

  double get sousTotal => prixApplique * quantite;
  double get benefice => (prixApplique - medicament.prixGrossiste) * quantite;
}

class PanierNotifier extends StateNotifier<List<PanierItem>> {
  PanierNotifier() : super([]);

  void ajouterMedicament(MedicamentModel med, double prix) {
    final idx = state.indexWhere((i) => i.medicament.id == med.id);
    if (idx >= 0) {
      incrementer(idx);
    } else {
      state = [...state, PanierItem(medicament: med, prixApplique: prix)];
    }
  }

  void incrementer(int idx) {
    final updated = [...state];
    updated[idx].quantite++;
    state = updated;
  }

  void decrementer(int idx) {
    final updated = [...state];
    if (updated[idx].quantite > 1) {
      updated[idx].quantite--;
      state = updated;
    } else {
      supprimerItem(idx);
    }
  }

  void supprimerItem(int idx) {
    final updated = [...state];
    updated.removeAt(idx);
    state = updated;
  }

  void vider() => state = [];

  double get total => state.fold(0, (sum, i) => sum + i.sousTotal);
  double get beneficeTotal => state.fold(0, (sum, i) => sum + i.benefice);
}

final panierProvider = StateNotifierProvider<PanierNotifier, List<PanierItem>>((_) => PanierNotifier());
final typeVenteProvider = StateProvider<String>((ref) => TypeVente.detail);
final searchVenteProvider = StateProvider<String>((ref) => '');

class VenteScreen extends ConsumerWidget {
  const VenteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panier = ref.watch(panierProvider);
    final notifier = ref.read(panierProvider.notifier);
    final typeVente = ref.watch(typeVenteProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Nouvelle vente'),
        actions: [
          if (panier.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
              onPressed: () => notifier.vider(),
            ),
        ],
      ),
      body: Column(
        children: [
          const _TypeVenteToggle(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: PfSearchBar(
              hint: 'Rechercher un médicament...',
              onChanged: (v) => ref.read(searchVenteProvider.notifier).state = v,
            ),
          ),
          const _SearchResults(),
          if (panier.isNotEmpty) _PanierHeader(count: panier.length, total: notifier.total),
          Expanded(
            child: panier.isEmpty 
              ? const _EmptyPanier() 
              : _PanierList(panier: panier, notifier: notifier),
          ),
          if (panier.isNotEmpty) _BoutonFinaliser(typeVente: typeVente),
        ],
      ),
    );
  }
}

class _TypeVenteToggle extends ConsumerWidget {
  const _TypeVenteToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: AppBorderRadius.md,
      ),
      child: Row(
        children: [
          _toggleBtn(ref, TypeVente.detail, 'Détail', Icons.shopping_bag_outlined),
          _toggleBtn(ref, TypeVente.gros, 'Gros', Icons.inventory_2_outlined),
        ],
      ),
    );
  }

  Widget _toggleBtn(WidgetRef ref, String value, String label, IconData icon) {
    final isSelected = ref.watch(typeVenteProvider) == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(typeVenteProvider.notifier).state = value,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: AppBorderRadius.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: isSelected ? Colors.white : AppColors.textMuted,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchVenteProvider);
    final typeVente = ref.watch(typeVenteProvider);
    if (query.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _searchMedicaments(ref, query),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final results = snapshot.data!;

        return Container(
          constraints: const BoxConstraints(maxHeight: 250),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppBorderRadius.md,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: results.length,
            itemBuilder: (context, index) {
              final mData = results[index];
              final prix = typeVente == TypeVente.gros 
                ? (mData['prix_grossiste'] as num).toDouble() 
                : (mData['prix_detail'] as num).toDouble();
              
              return ListTile(
                title: Text(mData['nom'], style: AppTextStyles.label),
                subtitle: Text('${prix.toStringAsFixed(0)} FC', style: AppTextStyles.small.copyWith(color: AppColors.primary)),
                trailing: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 0),
                onTap: () {
                  final med = MedicamentModel.fromMap(mData, mData['id']);
                  ref.read(panierProvider.notifier).ajouterMedicament(med, prix);
                  ref.read(searchVenteProvider.notifier).state = '';
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _searchMedicaments(WidgetRef ref, String query) async {
    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return [];
    return LocalDatabase.searchMedicaments(pharmacie.id, query);
  }
}

class _PanierHeader extends StatelessWidget {
  final int count;
  final double total;
  const _PanierHeader({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          Text('Panier ($count)', style: AppTextStyles.h4),
          const Spacer(),
          Text(
            '${total.toStringAsFixed(0)} FC', 
            style: AppTextStyles.h4.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _PanierList extends StatelessWidget {
  final List<PanierItem> panier;
  final PanierNotifier notifier;
  const _PanierList({required this.panier, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: panier.length,
      itemBuilder: (context, index) {
        final item = panier[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            title: Text(item.medicament.nom, style: AppTextStyles.label),
            subtitle: Text(
              '${item.prixApplique.toStringAsFixed(0)} FC x ${item.quantite}',
              style: AppTextStyles.small.copyWith(color: AppColors.textSecondary),
            ),
            trailing: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppBorderRadius.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: () => notifier.decrementer(index),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                  ),
                  Text('${item.quantite}', style: AppTextStyles.bodyMedium),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => notifier.incrementer(index),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyPanier extends StatelessWidget {
  const _EmptyPanier();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textMuted.withOpacity(0.2)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Votre panier est vide', 
            style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _BoutonFinaliser extends ConsumerStatefulWidget {
  final String typeVente;
  const _BoutonFinaliser({required this.typeVente});

  @override
  ConsumerState<_BoutonFinaliser> createState() => _BoutonFinaliserState();
}

class _BoutonFinaliserState extends ConsumerState<_BoutonFinaliser> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(panierProvider.notifier);
    
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: PfButton(
        label: 'Finaliser la vente (${notifier.total.toStringAsFixed(0)} FC)',
        isLoading: _loading,
        onPressed: () => _procederVente(context, notifier),
        fullWidth: true,
      ),
    );
  }

  Future<void> _procederVente(BuildContext context, PanierNotifier notifier) async {
    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;

    setState(() => _loading = true);
    try {
      final venteId = const Uuid().v4();
      final items = notifier.state.map((item) => VenteItemModel(
        medicamentId: item.medicament.id,
        medicamentNom: item.medicament.nom,
        quantite: item.quantite,
        unite: item.unite,
        prixUnitaire: item.prixApplique,
        prixAchat: item.medicament.prixGrossiste,
        sousTotal: item.sousTotal,
      )).toList();

      final vente = VenteModel(
        id: venteId,
        pharmacieId: pharmacie.id,
        typeVente: widget.typeVente,
        items: items,
        totalHT: notifier.total,
        totalTTC: notifier.total,
        benefice: notifier.beneficeTotal,
        date: DateTime.now(),
      );

      // Appel au Repository pour gérer la vente + la déduction de stock
      await ref.read(venteRepositoryProvider).effectuerVente(vente);

      notifier.vider();
      if (mounted) {
        PfSnackbar.success(context, 'Vente enregistrée avec succès');
      }
    } catch (e) {
      if (mounted) PfSnackbar.error(context, 'Erreur lors de la vente: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
