import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/features/stock/presentation/lots_screen.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/repositories/stock_repository.dart';
import 'fixtures.dart';

class _Stock extends StockRepository {
  int activations = 0;
  StockLot? received;
  int? corrected;
  String? reason;
  _Stock() : super(RepositoryAccess((_, __) {}));
  @override
  Future<void> activate(MedicamentModel expected) async {
    activations++;
  }

  @override
  Future<void> receive(MedicamentModel expected, StockLot lot) async {
    received = lot;
  }

  @override
  Future<void> adjust(
    MedicamentModel expected,
    String lotId,
    int quantity,
    String reason,
  ) async {
    corrected = quantity;
    this.reason = reason;
  }
}

void main() {
  late _Stock stock;
  setUp(() => stock = _Stock());
  Future<void> mount(WidgetTester tester, MedicamentModel medicine) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lotsDataProvider(
            medicine.id,
          ).overrideWith((ref) async => (medicine, <ActiviteModel>[])),
          stockRepositoryProvider.overrideWithValue(stock),
        ],
        child: MaterialApp(home: LotsScreen(id: medicine.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets(
    'Activation explicite, avertissement multi-appareils et annulation',
    (tester) async {
      await mount(tester, medicament());
      await tester.tap(find.text('Activer le suivi par lots'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('mettez tous les appareils à jour'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(stock.activations, 0);
      await tester.tap(find.text('Activer le suivi par lots'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activer'));
      await tester.pumpAndSettle();
      expect(stock.activations, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Réception valide convertit boîtes et coût en unités de base', (
    tester,
  ) async {
    await mount(
      tester,
      medicament(unites: const UnitesStock()).copyWith(lots: []),
    );
    await tester.tap(find.text('Réceptionner un lot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(stock.received, isNull);
    await tester.enterText(field('Numéro du lot'), 'LOT-123');
    await tester.enterText(field('Quantité (boite)'), '2');
    await tester.enterText(field('Prix d’achat (FC / boite)'), '50,5');
    await tester.ensureVisible(find.text('Date de péremption (obligatoire)'));
    await tester.tap(find.text('Date de péremption (obligatoire)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(stock.received?.quantiteBase, 200);
    expect(stock.received?.coutBase, 0.505);
    expect(stock.received?.numero, 'LOT-123');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Lot expiré visible, correction à zéro exige un motif et historique accessible',
    (tester) async {
      final medicine = medicament(unites: const UnitesStock(comprimes: 20))
          .copyWith(
            lots: [
              StockLot(
                id: 'lot',
                numero: 'LOT',
                quantiteBase: 20,
                coutBase: 1,
                reception: DateTime(2020),
                expiration: DateTime(2021),
              ),
            ],
          );
      await mount(tester, medicine);
      expect(find.text('Vendable : 0'), findsOneWidget);
      expect(find.textContaining('EXCLU DES VENTES'), findsOneWidget);
      await tester.tap(find.byTooltip('Corriger le stock physique'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Nouveau stock physique (comprimes)'), '0');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(stock.corrected, isNull);
      await tester.enterText(
        field('Motif obligatoire'),
        'Destruction pour péremption',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(stock.corrected, 0);
      expect(stock.reason, 'Destruction pour péremption');
      await tester.tap(find.text('Mouvements'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun mouvement enregistré.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
