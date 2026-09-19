import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/core/errors/stock_insuffisant_error.dart';
import 'package:pharmaflow/repositories/medicament_repository.dart';
import 'package:pharmaflow/repositories/vente_repository.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late MedicamentRepository medicines;
  late VenteRepository sales;
  late bool writable;
  late bool wholesale;
  setUp(() async {
    db = await LocalDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    writable = true;
    wholesale = false;
    final access = RepositoryAccess((owner, write) {
      if (owner != 'pharma-1' || (write && !writable))
        throw StateError('Accès refusé');
    });
    medicines = MedicamentRepository(access, database: () async => db);
    sales = VenteRepository(
      access,
      database: () async => db,
      wholesaleAllowed: () => wholesale,
    );
  });
  tearDown(() => db.close());

  test(
    'La finalisation indique le stock réel sans enregistrer la vente refusée',
    () async {
      await medicines.saveMedicament(
        medicament(unites: const UnitesStock(boites: 2)),
      );
      await expectLater(
        sales.effectuerVente(vente(items: [venteItem(quantite: 3)])),
        throwsA(
          isA<StockInsuffisantError>()
              .having((error) => error.quantiteDemandee, 'demandée', 3)
              .having((error) => error.quantiteDisponible, 'disponible', 2),
        ),
      );
      expect(await db.query('ventes'), isEmpty);
      expect(await db.query('vente_items'), isEmpty);
      expect(await db.query('sync_queue'), hasLength(1));
      expect(
        (await medicines.getMedicamentById(
          'pharma-1',
          'med-1',
        ))!.unites.totalBoites,
        2,
      );
    },
  );

  test(
    'Le gros désactivé refuse une nouvelle vente mais permet un rejeu identique',
    () async {
      await medicines.saveMedicament(medicament());
      final sale = vente(typeVente: 'gros', items: [venteItem(prix: 80)]);
      await expectLater(sales.effectuerVente(sale), throwsStateError);
      expect(await db.query('ventes'), isEmpty);
      expect(await db.query('sync_queue'), hasLength(1));
      wholesale = true;
      await sales.effectuerVente(sale);
      wholesale = false;
      await sales.effectuerVente(sale);
      expect(await db.query('ventes'), hasLength(1));
      expect(
        (await medicines.getMedicamentById(
          'pharma-1',
          'med-1',
        ))!.unites.totalBoites,
        8,
      );
      expect(await db.query('sync_queue'), hasLength(2));
    },
  );
  test('Le gros sans prix échoue sans mouvement de stock', () async {
    wholesale = true;
    await medicines.saveMedicament(medicament(prixGrossiste: null));
    await expectLater(
      sales.effectuerVente(vente(typeVente: 'gros')),
      throwsStateError,
    );
    expect(await db.query('ventes'), isEmpty);
    expect(
      (await medicines.getMedicamentById(
        'pharma-1',
        'med-1',
      ))!.unites.totalBoites,
      10,
    );
    expect(await db.query('sync_queue'), hasLength(1));
  });
  test('Un identifiant existant ne masque pas une vente différente', () async {
    await medicines.saveMedicament(medicament());
    await sales.effectuerVente(vente());
    await expectLater(
      sales.effectuerVente(vente(items: [venteItem(quantite: 1)])),
      throwsStateError,
    );
    expect(await db.query('ventes'), hasLength(1));
    expect(
      (await medicines.getMedicamentById(
        'pharma-1',
        'med-1',
      ))!.unites.totalBoites,
      8,
    );
  });

  test('Vente, articles, stock et outbox sont enregistrés ensemble', () async {
    await medicines.saveMedicament(medicament());
    await sales.effectuerVente(vente());
    final rows = await sales.getHistoriqueVentes('pharma-1');
    expect(rows.single.items.single.quantite, 2);
    expect(rows.single.totalTTC, 200);
    expect(
      (await medicines.getMedicamentById(
        'pharma-1',
        'med-1',
      ))!.unites.totalBoites,
      8,
    );
    expect(
      await LocalDatabase.getPendingSync('pharma-1', executor: db),
      hasLength(2),
    );
    expect((await db.query('ventes')).single['synced'], 0);
    await sales.effectuerVente(vente());
    expect(await db.query('ventes'), hasLength(1));
    expect(
      (await medicines.getMedicamentById(
        'pharma-1',
        'med-1',
      ))!.unites.totalBoites,
      8,
    );
  });

  test(
    'Un article indisponible annule toute la vente et ses mouvements',
    () async {
      await medicines.saveMedicament(medicament());
      await expectLater(
        sales.effectuerVente(
          vente(
            items: [
              venteItem(),
              venteItem(id: 'absent'),
            ],
          ),
        ),
        throwsStateError,
      );
      expect(await db.query('ventes'), isEmpty);
      expect(await db.query('vente_items'), isEmpty);
      expect(
        (await medicines.getMedicamentById(
          'pharma-1',
          'med-1',
        ))!.unites.totalBoites,
        10,
      );
      expect(await db.query('sync_queue'), hasLength(1));
    },
  );

  test('Stock insuffisant, péremption et accès révoqué refusés', () async {
    await medicines.saveMedicament(medicament());
    await expectLater(
      sales.effectuerVente(vente(items: [venteItem(quantite: 11)])),
      throwsStateError,
    );
    await medicines.saveMedicament(
      medicament(id: 'expired', expiration: DateTime(2020)),
    );
    await expectLater(
      sales.effectuerVente(vente(items: [venteItem(id: 'expired')])),
      throwsStateError,
    );
    writable = false;
    await expectLater(sales.effectuerVente(vente()), throwsStateError);
    await expectLater(
      medicines.deleteMedicament('pharma-1', 'med-1'),
      throwsStateError,
    );
    expect(await db.query('ventes'), isEmpty);
  });

  test('Une modification obsolète ne remplace pas un stock vendu', () async {
    await medicines.saveMedicament(medicament());
    final before = (await medicines.getMedicamentById('pharma-1', 'med-1'))!;
    await sales.effectuerVente(vente());
    await expectLater(
      medicines.saveMedicament(before, isEdit: true),
      throwsStateError,
    );
    expect(
      (await medicines.getMedicamentById(
        'pharma-1',
        'med-1',
      ))!.unites.totalBoites,
      8,
    );
  });

  test('Archiver garde les dates et ajoute une opération durable', () async {
    await medicines.saveMedicament(medicament());
    await medicines.deleteMedicament('pharma-1', 'med-1');
    expect(await medicines.getMedicaments('pharma-1'), isEmpty);
    final row = (await db.query('medicaments')).single;
    expect(row['est_actif'], 0);
    expect(row['created_at'], DateTime(2025, 1, 1).toIso8601String());
    expect(await db.query('sync_queue'), hasLength(2));
  });

  test(
    'Deux ventes simultanées ne peuvent pas consommer le même dernier stock',
    () async {
      await medicines.saveMedicament(
        medicament(unites: const UnitesStock(boites: 2)),
      );
      final results = await Future.wait([
        sales
            .effectuerVente(vente(id: 'first'))
            .then((_) => true)
            .catchError((_) => false),
        sales
            .effectuerVente(vente(id: 'second'))
            .then((_) => true)
            .catchError((_) => false),
      ]);
      expect(results.where((success) => success), hasLength(1));
      expect(await db.query('ventes'), hasLength(1));
    },
  );

  test('Le repository refuse les données d’une autre pharmacie', () async {
    await expectLater(
      medicines.saveMedicament(medicament(pharmacieId: 'pharma-2')),
      throwsStateError,
    );
    await expectLater(medicines.getMedicaments('pharma-2'), throwsStateError);
    expect(await db.query('medicaments'), isEmpty);
  });
}
