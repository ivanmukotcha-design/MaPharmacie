import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/core/errors/stock_insuffisant_error.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/features/sales/presentation/panier.dart';
import 'fixtures.dart';

void main() {
  test('Le dépassement précise les quantités sans modifier le panier', () {
    final cart = PanierNotifier();
    addTearDown(cart.dispose);
    cart.ajouterMedicament(medicament(unites: const UnitesStock(boites: 1)));
    expect(
      () => cart.incrementer(0),
      throwsA(
        isA<StockInsuffisantError>()
            .having((error) => error.produit, 'produit', 'Produit med-1')
            .having((error) => error.quantiteDemandee, 'demandée', 2)
            .having((error) => error.quantiteDisponible, 'disponible', 1)
            .having(
              (error) => error.message,
              'message',
              contains('Stock disponible : 1 boîte'),
            ),
      ),
    );
    expect(cart.items.single.quantite, 1);
    expect(cart.total, 100);
    expect(
      () => cart.changerUnite(0, 'carton'),
      throwsA(
        isA<StockInsuffisantError>()
            .having((error) => error.unite, 'unité', 'carton')
            .having((error) => error.quantiteDisponible, 'disponible', 0),
      ),
    );
    expect(cart.items.single.unite, 'boite');
  });

  test('Le message compte aussi les boîtes dans les cartons', () {
    final cart = PanierNotifier();
    addTearDown(cart.dispose);
    cart.ajouterMedicament(
      medicament(unites: const UnitesStock(cartons: 1, boites: 2)),
    );
    for (var quantite = 1; quantite < 22; quantite++) {
      cart.incrementer(0);
    }
    expect(
      () => cart.incrementer(0),
      throwsA(
        isA<StockInsuffisantError>()
            .having((error) => error.quantiteDisponible, 'disponible', 22)
            .having(
              (error) => error.message,
              'message',
              contains('Quantité demandée : 23 boîtes'),
            ),
      ),
    );
    expect(cart.items.single.quantite, 22);
  });

  test('Un premier ajout sans stock donne aussi une erreur explicite', () {
    final cart = PanierNotifier();
    addTearDown(cart.dispose);
    expect(
      () => cart.ajouterMedicament(medicament(unites: const UnitesStock())),
      throwsA(
        isA<StockInsuffisantError>()
            .having((error) => error.quantiteDemandee, 'demandée', 1)
            .having((error) => error.quantiteDisponible, 'disponible', 0),
      ),
    );
    expect(cart.items, isEmpty);
  });

  test(
    'Un changement distant du réglage conserve le panier au tarif détail',
    () {
      final setting = StateProvider<bool>((ref) => true);
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
          wholesaleEnabledProvider.overrideWith((ref) => ref.watch(setting)),
        ],
      );
      addTearDown(container.dispose);
      final cart = container.read(panierProvider.notifier);
      cart.ajouterMedicament(medicament());
      cart.changerType(true);
      container.read(typeVenteProvider.notifier).state = 'gros';
      expect(cart.total, 80);
      container.read(setting.notifier).state = false;
      expect(container.read(typeVenteProvider), 'detail');
      expect(identical(container.read(panierProvider.notifier), cart), isTrue);
      expect(container.read(panierProvider), hasLength(1));
      expect(cart.total, 100);
    },
  );
  test(
    'Le détail est la valeur par défaut et le gros exige son activation',
    () {
      final cart = PanierNotifier();
      addTearDown(cart.dispose);
      cart.ajouterMedicament(medicament(prixGrossiste: null));
      expect(cart.total, 100);
      expect(() => cart.changerType(true), throwsStateError);
      expect(cart.total, 100);
    },
  );
  test('Un prix de gros absent ne modifie pas partiellement le panier', () {
    final cart = PanierNotifier(canSellWholesale: () => true);
    addTearDown(cart.dispose);
    cart.ajouterMedicament(medicament());
    cart.ajouterMedicament(medicament(id: 'sans-gros', prixGrossiste: null));
    expect(() => cart.changerType(true), throwsStateError);
    expect(cart.total, 200);
    cart.changerUnite(0, 'plaquette');
    expect(cart.items.first.prixApplique, 10);
  });
  test(
    'Désactiver le gros pendant une vente revient au détail au déverrouillage',
    () {
      var enabled = true;
      final cart = PanierNotifier(canSellWholesale: () => enabled);
      addTearDown(cart.dispose);
      cart.ajouterMedicament(medicament());
      cart.changerType(true);
      cart.verrouiller(true);
      enabled = false;
      cart.changerType(false);
      expect(cart.total, 80);
      cart.verrouiller(false);
      expect(cart.total, 100);
      expect(() => cart.changerType(true), throwsStateError);
    },
  );
  test('Changement gros/détail et unité recalcule prix et marge', () {
    final cart = PanierNotifier(canSellWholesale: () => true);
    addTearDown(cart.dispose);
    cart.ajouterMedicament(medicament());
    expect(cart.total, 100);
    expect(cart.beneficeTotal, 50);
    cart.changerType(true);
    expect(cart.total, 80);
    expect(cart.beneficeTotal, 30);
    cart.changerUnite(0, 'comprimes');
    expect(cart.items.single.quantite, 1);
    expect(
      cart.items.single.prixApplique,
      medicament().prixPourUnite('comprimes', gros: true),
    );
    cart.changerType(false);
    expect(cart.total, medicament().prixPourUnite('comprimes', gros: false));
  });

  test('Panier verrouillé pendant la vente et quantité limitée au stock', () {
    final cart = PanierNotifier();
    addTearDown(cart.dispose);
    cart.ajouterMedicament(medicament());
    cart.verrouiller(true);
    cart.vider();
    cart.incrementer(0);
    cart.changerType(true);
    expect(cart.items.single.quantite, 1);
    expect(cart.total, 100);
    cart.verrouiller(false);
    for (var count = 1; count < 10; count++) {
      cart.incrementer(0);
    }
    expect(() => cart.incrementer(0), throwsStateError);
    expect(cart.items.single.quantite, 10);
  });
}
