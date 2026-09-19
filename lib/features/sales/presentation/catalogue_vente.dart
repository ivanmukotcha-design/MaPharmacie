import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../local_database/local_database.dart';
import '../../../models/models.dart';
import '../../../repositories/medicament_repository.dart';
import '../../../shared/widgets/pf_search_bar.dart';
import 'panier.dart';

final catalogueVenteProvider = FutureProvider.autoDispose
    .family<List<MedicamentModel>, String>((ref, pharmacieId) {
      ref.watch(localChangesProvider);
      return ref
          .watch(medicamentRepositoryProvider)
          .getMedicaments(pharmacieId);
    });

final categorieVenteProvider = StateProvider.autoDispose<String?>((ref) {
  ref.watch(currentUserProvider.select((user) => user?.uid));
  return null;
});

class CatalogueVente extends ConsumerWidget {
  final ValueChanged<MedicamentModel> onAjouter;

  const CatalogueVente({super.key, required this.onAjouter});

  String _categorie(MedicamentModel medicament) =>
      medicament.categorie.trim().isEmpty
      ? 'Sans catégorie'
      : medicament.categorie.trim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmacieId = ref.watch(currentUserProvider)?.uid;
    if (pharmacieId == null) {
      return const Center(
        child: Text('Connectez-vous pour voir les produits.'),
      );
    }
    final catalogue = ref.watch(catalogueVenteProvider(pharmacieId));
    final query = ref.watch(searchVenteProvider).trim().toLowerCase();
    final categorie = ref.watch(categorieVenteProvider);
    final gros = ref.watch(typeVenteProvider) == 'gros';
    final busy = ref.watch(venteEnCoursProvider);

    return CustomScrollView(
      key: const PageStorageKey('catalogue_vente'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: PfSearchBar(
              value: ref.watch(searchVenteProvider),
              hint: 'Nom ou code-barres (facultatif)',
              onChanged: (value) =>
                  ref.read(searchVenteProvider.notifier).state = value,
            ),
          ),
        ),
        ...catalogue.when<List<Widget>>(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (error, stackTrace) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Impossible de charger le catalogue.'),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(catalogueVenteProvider(pharmacieId)),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          data: (medicaments) {
            final categories = medicaments.map(_categorie).toSet().toList()
              ..sort();
            final selection = categories.contains(categorie) ? categorie : null;
            final produits = medicaments.where((medicament) {
              return (selection == null ||
                      _categorie(medicament) == selection) &&
                  (query.isEmpty ||
                      medicament.nom.toLowerCase().contains(query) ||
                      medicament.codeBarres?.toLowerCase() == query);
            }).toList();

            return [
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      for (final category in <String?>[null, ...categories])
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: ChoiceChip(
                            label: Text(category ?? 'Toutes'),
                            selected: selection == category,
                            onSelected: (_) =>
                                ref
                                        .read(categorieVenteProvider.notifier)
                                        .state =
                                    category,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (produits.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        medicaments.isEmpty
                            ? 'Aucun produit enregistré. Ajoutez vos produits dans Stock.'
                            : 'Aucun produit ne correspond à ces filtres.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  sliver: SliverList.builder(
                    itemCount: produits.length,
                    itemBuilder: (context, index) {
                      final medicament = produits[index];
                      final prix = gros
                          ? medicament.prixGrossiste
                          : medicament.prixDetail;
                      final String? indisponible;
                      if (!medicament.estActif || medicament.estExpire) {
                        indisponible = 'Produit indisponible ou expiré';
                      } else if (medicament.estEnRupture) {
                        indisponible = 'Rupture de stock';
                      } else if (prix == null) {
                        indisponible = 'Tarif de gros non renseigné';
                      } else if (medicament.prixAchat == null) {
                        indisponible = "Prix d'achat non renseigné";
                      } else {
                        indisponible = null;
                      }
                      final ajouter = busy || indisponible != null
                          ? null
                          : () => onAjouter(medicament);

                      return Card(
                        key: ValueKey('produit_${medicament.id}'),
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ListTile(
                          onTap: ajouter,
                          title: Text(
                            medicament.nom,
                            style: AppTextStyles.label,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_categorie(medicament)),
                              if (prix != null)
                                Text(
                                  '${prix.toStringAsFixed(2)} FC / ${medicament.unitePrix}',
                                  style: AppTextStyles.small.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              Text('Stock : ${medicament.unites.affichage}'),
                              if (indisponible != null)
                                Text(
                                  indisponible,
                                  style: AppTextStyles.small.copyWith(
                                    color: AppColors.danger,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            key: ValueKey('ajouter_${medicament.id}'),
                            tooltip: 'Ajouter ${medicament.nom} au panier',
                            onPressed: ajouter,
                            icon: const Icon(Icons.add_circle_outline),
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ];
          },
        ),
      ],
    );
  }
}
