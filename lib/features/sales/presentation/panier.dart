import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/auth_provider.dart';
import '../../../core/errors/stock_insuffisant_error.dart';
import '../../../models/models.dart';

class PanierItem {
  final MedicamentModel medicament;
  final int quantite;
  final String unite;
  final double prixApplique;
  const PanierItem({
    required this.medicament,
    required this.unite,
    this.quantite = 1,
    required this.prixApplique,
  });
  double get sousTotal => prixApplique * quantite;
  double get benefice =>
      (prixApplique - medicament.coutPourUnite(unite)) * quantite;
  PanierItem copyWith({int? quantite, String? unite, double? prix}) =>
      PanierItem(
        medicament: medicament,
        quantite: quantite ?? this.quantite,
        unite: unite ?? this.unite,
        prixApplique: prix ?? prixApplique,
      );
}

class PanierNotifier extends StateNotifier<List<PanierItem>> {
  final bool Function() _canSellWholesale;
  PanierNotifier({bool Function()? canSellWholesale})
    : _canSellWholesale = canSellWholesale ?? (() => false),
      super([]);
  bool _gros = false;
  bool _busy = false;
  List<PanierItem> get items => List.unmodifiable(state);
  void verrouiller(bool value) {
    _busy = value;
    if (mounted && !value && _gros && !_canSellWholesale()) changerType(false);
  }

  void ajouterMedicament(MedicamentModel med) {
    if (_busy) return;
    if (_gros && !_canSellWholesale()) changerType(false);
    med.validate();
    final prix = med.prixPourUnite(med.unitePrix, gros: _gros);
    if (!med.estActif || med.estExpire)
      throw StateError('Ce produit ne peut pas être vendu.');
    med.coutPourUnite(med.unitePrix);
    final index = state.indexWhere((entry) => entry.medicament.id == med.id);
    if (index >= 0) {
      incrementer(index);
    } else {
      _verifierStock(med, med.unitePrix, 1);
      state = [
        ...state,
        PanierItem(medicament: med, unite: med.unitePrix, prixApplique: prix),
      ];
    }
  }

  void incrementer(int index) {
    if (_busy) return;
    final item = state[index];
    if (item.medicament.estExpire) {
      throw StateError(
        '${item.medicament.nom} est expiré et ne peut pas être vendu.',
      );
    }
    _verifierStock(item.medicament, item.unite, item.quantite + 1);
    state = [
      for (var position = 0; position < state.length; position++)
        position == index
            ? item.copyWith(quantite: item.quantite + 1)
            : state[position],
    ];
  }

  void decrementer(int index) {
    if (_busy) return;
    final item = state[index];
    if (item.quantite == 1) {
      supprimerItem(index);
      return;
    }
    state = [
      for (var position = 0; position < state.length; position++)
        position == index
            ? item.copyWith(quantite: item.quantite - 1)
            : state[position],
    ];
  }

  void changerType(bool gros) {
    if (_busy) return;
    if (gros && !_canSellWholesale())
      throw StateError('Les tarifs de gros sont désactivés.');
    final updated = state
        .map(
          (item) => item.copyWith(
            prix: item.medicament.prixPourUnite(item.unite, gros: gros),
          ),
        )
        .toList();
    _gros = gros;
    state = updated;
  }

  void changerUnite(int index, String unite) {
    if (_busy) return;
    final item = state[index];
    _verifierStock(item.medicament, unite, 1);
    final updated = item.copyWith(
      quantite: 1,
      unite: unite,
      prix: item.medicament.prixPourUnite(unite, gros: _gros),
    );
    state = [
      for (var position = 0; position < state.length; position++)
        position == index ? updated : state[position],
    ];
  }

  void _verifierStock(MedicamentModel medicament, String unite, int quantite) {
    final disponible = medicament.unites.disponible(unite);
    if (quantite > disponible) {
      throw StockInsuffisantError(
        produit: medicament.nom,
        quantiteDemandee: quantite,
        quantiteDisponible: disponible,
        unite: unite,
      );
    }
  }

  void supprimerItem(int index) {
    if (!_busy) state = [...state]..removeAt(index);
  }

  void vider() {
    if (!_busy) state = [];
  }

  double get total => state.fold(0, (total, item) => total + item.sousTotal);
  double get beneficeTotal =>
      state.fold(0, (total, item) => total + item.benefice);
}

final panierProvider = StateNotifierProvider<PanierNotifier, List<PanierItem>>((
  ref,
) {
  ref.watch(currentUserProvider.select((user) => user?.uid));
  final cart = PanierNotifier(
    canSellWholesale: () => ref.read(wholesaleEnabledProvider),
  );
  ref.listen<bool>(wholesaleEnabledProvider, (_, enabled) {
    if (!enabled) cart.changerType(false);
  });
  return cart;
});
final typeVenteProvider = StateProvider<String>((ref) {
  ref.watch(wholesaleEnabledProvider);
  ref.watch(currentUserProvider.select((user) => user?.uid));
  return 'detail';
});
final searchVenteProvider = StateProvider<String>((ref) {
  ref.watch(currentUserProvider.select((user) => user?.uid));
  return '';
});
final venteEnCoursProvider = StateProvider<bool>((ref) {
  ref.watch(currentUserProvider.select((user) => user?.uid));
  return false;
});
