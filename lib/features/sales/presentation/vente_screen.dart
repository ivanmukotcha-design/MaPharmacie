import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/stock_insuffisant_error.dart';
import '../../../models/models.dart';
import '../../../repositories/vente_repository.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_snackbar.dart';
import 'catalogue_vente.dart';
import 'panier.dart';

void _panierAction(BuildContext context, VoidCallback action) {
  try {
    action();
  } catch (error) {
    _afficherErreurVente(context, error);
  }
}

void _afficherErreurVente(
  BuildContext context,
  Object error, {
  String fallback = 'Impossible de modifier le panier. Veuillez réessayer.',
}) {
  if (error is StockInsuffisantError) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.inventory_2_outlined, color: AppColors.warning),
        title: const Text('Stock insuffisant'),
        content: SingleChildScrollView(child: Text(error.message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
    return;
  }
  final message = switch (error) {
    StateError() => error.message,
    FormatException() => error.message,
    _ => fallback,
  };
  PfSnackbar.error(context, message);
}

class VenteScreen extends ConsumerWidget {
  const VenteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panier = ref.watch(panierProvider);
    final notifier = ref.read(panierProvider.notifier);
    final typeVente = ref.watch(typeVenteProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Nouvelle vente'),
          bottom: TabBar(
            onTap: (_) => FocusScope.of(context).unfocus(),
            tabs: [
              const Tab(text: 'Catalogue'),
              Tab(text: 'Panier (${panier.length})'),
            ],
          ),
          actions: [
            if (panier.isNotEmpty)
              IconButton(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppColors.danger,
                ),
                onPressed: () => notifier.vider(),
              ),
          ],
        ),
        body: Column(
          children: [
            if (ref.watch(wholesaleEnabledProvider)) const _TypeVenteToggle(),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: CatalogueVente(
                          onAjouter: (medicament) => _panierAction(
                            context,
                            () => notifier.ajouterMedicament(medicament),
                          ),
                        ),
                      ),
                      if (panier.isNotEmpty &&
                          MediaQuery.viewInsetsOf(context).bottom == 0)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Builder(
                            builder: (context) => PfButton(
                              label:
                                  'Voir le panier (${panier.length}) · ${notifier.total.toStringAsFixed(0)} FC',
                              fullWidth: true,
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                DefaultTabController.of(context).animateTo(1);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  Column(
                    children: [
                      if (panier.isNotEmpty)
                        _PanierHeader(
                          count: panier.length,
                          total: notifier.total,
                        ),
                      Expanded(
                        child: panier.isEmpty
                            ? const _EmptyPanier()
                            : _PanierList(panier: panier, notifier: notifier),
                      ),
                      if (panier.isNotEmpty)
                        _BoutonFinaliser(typeVente: typeVente),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
          _toggleBtn(
            ref,
            TypeVente.detail,
            'Détail',
            Icons.shopping_bag_outlined,
          ),
          _toggleBtn(ref, TypeVente.gros, 'Gros', Icons.inventory_2_outlined),
        ],
      ),
    );
  }

  Widget _toggleBtn(WidgetRef ref, String value, String label, IconData icon) {
    final isSelected = ref.watch(typeVenteProvider) == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (ref.read(venteEnCoursProvider)) return;
          _panierAction(ref.context, () {
            ref
                .read(panierProvider.notifier)
                .changerType(value == TypeVente.gros);
            ref.read(typeVenteProvider.notifier).state = value;
          });
        },
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

class _PanierHeader extends StatelessWidget {
  final int count;
  final double total;
  const _PanierHeader({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text('Panier ($count)', style: AppTextStyles.h4),
          const Spacer(),
          Text(
            '${total.toStringAsFixed(0)} FC',
            style: AppTextStyles.h4.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 4,
            ),
            title: Text(item.medicament.nom, style: AppTextStyles.label),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.prixApplique.toStringAsFixed(2)} FC x ${item.quantite}',
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                DropdownButton<String>(
                  value: item.unite,
                  items:
                      (item.medicament.unitePrix == 'flacon'
                              ? ['flacon']
                              : ['carton', 'boite', 'plaquette', 'comprimes'])
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(unit),
                            ),
                          )
                          .toList(),
                  onChanged: (unit) {
                    if (unit != null)
                      _panierAction(
                        context,
                        () => notifier.changerUnite(index, unit),
                      );
                  },
                ),
              ],
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
                    onPressed: () => _panierAction(
                      context,
                      () => notifier.incrementer(index),
                    ),
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
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: AppColors.textMuted.withOpacity(0.2),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Votre panier est vide',
            style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => DefaultTabController.of(context).animateTo(0),
            child: const Text('Choisir des produits'),
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
        onPressed: () => _procederVente(notifier),
        fullWidth: true,
      ),
    );
  }

  Future<void> _procederVente(PanierNotifier notifier) async {
    if (ref.read(venteEnCoursProvider)) return;
    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;
    final busy = ref.read(venteEnCoursProvider.notifier);
    final repository = ref.read(venteRepositoryProvider);
    busy.state = true;
    notifier.verrouiller(true);

    setState(() => _loading = true);
    try {
      final venteId = const Uuid().v4();
      final items = notifier.items
          .map(
            (item) => VenteItemModel(
              medicamentId: item.medicament.id,
              medicamentNom: item.medicament.nom,
              quantite: item.quantite,
              unite: item.unite,
              prixUnitaire: item.prixApplique,
              prixAchat: item.medicament.coutPourUnite(item.unite),
              sousTotal: item.sousTotal,
            ),
          )
          .toList();

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
      await repository.effectuerVente(vente);

      notifier.verrouiller(false);
      if (notifier.mounted) notifier.vider();
      if (mounted) {
        PfSnackbar.success(
          context,
          'Vente enregistrée sur cet appareil. Consultez l’état de synchronisation sur l’accueil.',
        );
      }
    } catch (error) {
      if (mounted) {
        _afficherErreurVente(
          context,
          error,
          fallback: "La vente n'a pas pu être enregistrée. Veuillez réessayer.",
        );
      }
    } finally {
      notifier.verrouiller(false);
      if (busy.mounted) busy.state = false;
      if (mounted) setState(() => _loading = false);
    }
  }
}
