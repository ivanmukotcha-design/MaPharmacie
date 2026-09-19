import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/core/errors/stock_insuffisant_error.dart';
import 'package:pharmaflow/features/sales/presentation/catalogue_vente.dart';
import 'package:pharmaflow/features/sales/presentation/panier.dart';
import 'package:pharmaflow/features/sales/presentation/vente_screen.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/medicament_repository.dart';
import 'package:pharmaflow/repositories/vente_repository.dart';

import 'fixtures.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  _User(this.uid);
}

class _Medicaments extends Fake implements MedicamentRepository {
  List<MedicamentModel> produits = [];
  final demandes = <String>[];
  bool erreur = false;
  Completer<List<MedicamentModel>>? attente;

  @override
  Future<List<MedicamentModel>> getMedicaments(String pharmacieId) async {
    demandes.add(pharmacieId);
    if (erreur) throw StateError('Lecture impossible');
    if (attente != null) return attente!.future;
    return produits
        .where(
          (produit) => produit.pharmacieId == pharmacieId && produit.estActif,
        )
        .toList();
  }
}

class _Ventes extends Fake implements VenteRepository {
  final Future<void> Function(VenteModel) enregistrer;
  _Ventes(this.enregistrer);

  @override
  Future<void> effectuerVente(VenteModel vente) => enregistrer(vente);
}

MedicamentModel _produit(String id, String nom, String categorie) =>
    MedicamentModel.fromMap({
      ...medicament(id: id).toMap(),
      'nom': nom,
      'categorie': categorie,
      'code_barres': '123456',
    }, id);

void main() {
  late _Medicaments repository;
  late StreamController<int> changements;
  late ProviderContainer container;
  VenteModel? venteEnregistree;
  Object? echecVente;
  final session = StateProvider<User?>((ref) => _User('pharma-1'));

  setUp(() {
    venteEnregistree = null;
    echecVente = null;
    repository = _Medicaments()
      ..produits = [
        _produit('para', 'Paracétamol 500 mg', 'Antalgiques'),
        _produit('amoxi', 'Amoxicilline 250 mg', 'Antibiotiques'),
      ];
    changements = StreamController<int>.broadcast();
    container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(session)),
        currentPharmacieProvider.overrideWith(
          (ref) => Stream.value(pharmacie()),
        ),
        wholesaleEnabledProvider.overrideWith((ref) => true),
        medicamentRepositoryProvider.overrideWithValue(repository),
        localChangesProvider.overrideWith((ref) => changements.stream),
        venteRepositoryProvider.overrideWithValue(
          _Ventes((value) async {
            if (echecVente != null) throw echecVente!;
            venteEnregistree = value;
            repository.produits = [
              medicament(id: 'para', unites: const UnitesStock()),
            ];
            changements.add(1);
          }),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await changements.close();
  });

  Future<void> mount(WidgetTester tester) async {
    await container.read(currentPharmacieProvider.future);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: VenteScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'Le dépassement affiche un message lisible et garde la quantité',
    (tester) async {
      repository.produits = [medicament(unites: const UnitesStock(boites: 1))];
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ajouter_med-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Voir le panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Stock insuffisant'), findsOneWidget);
      expect(
        find.textContaining('Quantité demandée : 2 boîtes'),
        findsOneWidget,
      );
      expect(find.textContaining('Stock disponible : 1 boîte'), findsOneWidget);
      expect(find.textContaining('Bad state'), findsNothing);
      expect(container.read(panierProvider).single.quantite, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Une baisse du stock à la validation explique le refus et garde le panier',
    (tester) async {
      echecVente = StockInsuffisantError(
        produit: 'Paracétamol 500 mg',
        quantiteDemandee: 1,
        quantiteDisponible: 0,
        unite: 'boite',
      );
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ajouter_para')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Voir le panier'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Finaliser la vente'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stock disponible : 0 boîte'), findsOneWidget);
      expect(find.textContaining('Bad state'), findsNothing);
      expect(venteEnregistree, isNull);
      expect(container.read(panierProvider), hasLength(1));
      expect(container.read(venteEnCoursProvider), isFalse);
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Le catalogue permet une vente sans saisir de recherche', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Paracétamol 500 mg'), findsOneWidget);
    expect(find.text('100.00 FC / boite'), findsWidgets);
    expect(find.text('Stock : 10 boîtes'), findsWidgets);
    expect(container.read(searchVenteProvider), isEmpty);
    await tester.tap(find.byKey(const ValueKey('ajouter_para')));
    await tester.pumpAndSettle();
    expect(container.read(panierProvider).single.quantite, 1);
    await tester.tap(find.textContaining('Voir le panier'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(container.read(panierProvider).single.quantite, 2);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('plaquette').last);
    await tester.pumpAndSettle();
    expect(container.read(panierProvider).single.unite, 'plaquette');
    expect(container.read(panierProvider.notifier).total, 10);
    expect(repository.demandes, ['pharma-1']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Les catégories se combinent avec la recherche facultative', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Antalgiques'));
    await tester.pumpAndSettle();
    expect(find.text('Paracétamol 500 mg'), findsOneWidget);
    expect(find.text('Amoxicilline 250 mg'), findsNothing);
    await tester.enterText(find.byType(TextField), 'AMOX');
    await tester.pumpAndSettle();
    expect(
      find.text('Aucun produit ne correspond à ces filtres.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Toutes'));
    await tester.pumpAndSettle();
    expect(find.text('Amoxicilline 250 mg'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' 123456 ');
    await tester.pumpAndSettle();
    expect(find.text('Paracétamol 500 mg'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(container.read(searchVenteProvider), isEmpty);
    expect(repository.demandes, ['pharma-1']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Rupture, péremption et tarif manquant empêchent un ajout', (
    tester,
  ) async {
    repository.produits = [medicament(unites: const UnitesStock())];
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.text('Rupture de stock'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ajouter_med-1')))
          .onPressed,
      isNull,
    );
    repository.produits = [medicament(expiration: DateTime(2020))];
    changements.add(1);
    await tester.pumpAndSettle();
    expect(find.text('Produit indisponible ou expiré'), findsOneWidget);
    repository.produits = [medicament(prixGrossiste: null)];
    changements.add(2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gros'));
    await tester.pumpAndSettle();
    expect(find.text('Tarif de gros non renseigné'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ajouter_med-1')))
          .onPressed,
      isNull,
    );
    expect(container.read(panierProvider), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Le catalogue vide et le panier vide restent utilisables', (
    tester,
  ) async {
    repository.produits = [];
    await mount(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun produit enregistré'), findsOneWidget);
    await tester.tap(find.text('Panier (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Votre panier est vide'), findsOneWidget);
    await tester.tap(find.text('Choisir des produits'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun produit enregistré'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Chargement, erreur et nouvelle tentative sont visibles', (
    tester,
  ) async {
    final attente = Completer<List<MedicamentModel>>();
    repository.attente = attente;
    await mount(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    attente.completeError(StateError('Lecture impossible'));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger le catalogue.'), findsOneWidget);
    repository.attente = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Paracétamol 500 mg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Un changement de compte efface panier, filtres et ancien catalogue',
    (tester) async {
      await mount(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ajouter_para')));
      await tester.enterText(find.byType(TextField), 'para');
      container.read(categorieVenteProvider.notifier).state = 'Antalgiques';
      final attente = Completer<List<MedicamentModel>>();
      repository.attente = attente;
      container.read(session.notifier).state = _User('pharma-2');
      await tester.pump();
      expect(find.text('Paracétamol 500 mg'), findsNothing);
      expect(container.read(panierProvider), isEmpty);
      expect(container.read(searchVenteProvider), isEmpty);
      expect(container.read(categorieVenteProvider), isNull);
      attente.complete([medicament(id: 'autre', pharmacieId: 'pharma-2')]);
      await tester.pumpAndSettle();
      expect(find.text('Produit autre'), findsOneWidget);
      expect(repository.demandes.last, 'pharma-2');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Le panier se finalise puis le catalogue actualise le stock', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ajouter_para')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Voir le panier'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Finaliser la vente'));
    await tester.pumpAndSettle();
    expect(venteEnregistree?.items.single.medicamentId, 'para');
    expect(venteEnregistree?.totalTTC, 100);
    expect(container.read(panierProvider), isEmpty);
    await tester.tap(find.text('Choisir des produits'));
    await tester.pumpAndSettle();
    expect(find.text('Rupture de stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Petit écran et clavier ouvert ne masquent pas le catalogue', (
    tester,
  ) async {
    await mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ajouter_para')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'para');
    await tester.pumpAndSettle();
    expect(find.text('Paracétamol 500 mg'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
