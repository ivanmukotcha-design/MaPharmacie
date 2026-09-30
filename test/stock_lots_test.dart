import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/medicament_repository.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/repositories/stock_repository.dart';
import 'package:pharmaflow/repositories/vente_repository.dart';
import 'package:pharmaflow/features/sales/presentation/panier.dart';
import 'package:pharmaflow/services/backup_service.dart';
import 'package:pharmaflow/services/sync_service.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.now();
  StockLot lot(String id, int quantity, double cost, {int? days = 20}) =>
      StockLot(
        id: id,
        numero: id,
        quantiteBase: quantity,
        coutBase: cost,
        reception: now,
        expiration: days == null ? null : now.add(Duration(days: days)),
      );
  MedicamentModel tracked(List<StockLot> lots) => medicament().copyWith(
    lots: lots,
    unites: const UnitesStock().avecTotalBase(
      lots.fold(0, (total, lot) => total + lot.quantiteBase),
      flacon: false,
    ),
  );
  VenteItemModel line(MedicamentModel medicine, int quantity) => VenteItemModel(
    medicamentId: medicine.id,
    medicamentNom: medicine.nom,
    quantite: quantity,
    unite: 'boite',
    prixUnitaire: 100,
    prixAchat: medicine.coutVente(quantity, 'boite') / quantity,
    sousTotal: quantity * 100,
    lots: medicine.lotsPourVente(quantity, 'boite'),
  );

  test(
    'FEFO, exclusion des expirés, date inconnue en dernier et coût pondéré',
    () {
      final medicine = tracked([
        lot('unknown', 200, 5, days: null),
        lot('late', 200, 2, days: 50),
        lot('early', 100, 1),
        lot('expired', 100, 9, days: -1),
      ])..validate();
      expect(medicine.stockTotal, 600);
      expect(medicine.unitesVendables.totalComprimes, 500);
      expect(medicine.estExpire, isFalse);
      expect(medicine.contientExpires, isTrue);
      final item = line(medicine, 2);
      expect(item.lots.map((entry) => entry.lotId), ['early', 'late']);
      expect(item.prixAchat, 150);
      final after = medicine.deduireArticle(item, now)..validate();
      expect(after.stockTotal, 400);
      expect(
        after.lots!.firstWhere((entry) => entry.id == 'expired').quantiteBase,
        100,
      );
      final cart = PanierItem(
        medicament: medicine,
        unite: 'boite',
        quantite: 2,
        prixApplique: 100,
      );
      expect(cart.coutTotal, 300);
      expect(cart.benefice, -100);
    },
  );

  test(
    'Un lot reste vendable jusqu’à la fin de sa date et aucun lot alternatif n’est choisi au débit',
    () {
      final entry = StockLot(
        id: 'dated',
        numero: 'dated',
        quantiteBase: 100,
        coutBase: 1,
        reception: DateTime(2026),
        expiration: DateTime(2026, 10, 1),
      );
      expect(entry.expiredAt(DateTime(2026, 10, 1, 23, 59)), isFalse);
      expect(entry.expiredAt(DateTime(2026, 10, 2)), isTrue);
      final medicine = tracked([lot('original', 100, 1), lot('other', 100, 1)]);
      final item = line(medicine, 1);
      final changed = tracked([lot('original', 0, 1), lot('other', 200, 1)]);
      expect(() => changed.deduireArticle(item, now), throwsStateError);
      expect(
        () => tracked([lot('expired', 100, 1, days: -1)]).coutVente(1, 'boite'),
        throwsStateError,
      );
    },
  );

  test('Sérialisation SQLite/cloud et cohérence du stock', () {
    final medicine = tracked([lot('lot', 110, 0.42)]);
    expect(
      MedicamentModel.fromSql(medicine.toSql()).lots!.single.toMap(),
      medicine.lots!.single.toMap(),
    );
    expect(
      MedicamentModel.fromMap(medicine.toMap(), medicine.id).stockTotal,
      110,
    );
    final item = line(medicine, 1);
    expect(VenteItemModel.fromMap(item.toSql()).toMap(), item.toMap());
    expect(
      () => medicament().copyWith(lots: [lot('bad', 1, 1)]).validate(),
      throwsFormatException,
    );
    expect(
      () => tracked([lot('same', 1, 1), lot('same', 1, 1)]).validate(),
      throwsFormatException,
    );
  });

  group('Stock transactionnel', () {
    late Database db;
    late StockRepository stock;
    late MedicamentRepository medicines;
    late VenteRepository sales;
    late SyncService sync;
    late FakeFirebaseFirestore cloud;
    final access = RepositoryAccess((owner, _) {
      if (owner != 'pharma-1') throw StateError('Accès refusé');
    });
    Future<MedicamentModel> current() async =>
        (await medicines.getMedicamentById('pharma-1', 'med-1'))!;
    setUp(() async {
      db = await LocalDatabase.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      stock = StockRepository(access, database: () async => db);
      medicines = MedicamentRepository(access, database: () async => db);
      sales = VenteRepository(access, database: () async => db);
      cloud = FakeFirebaseFirestore();
      sync = SyncService(
        cloud,
        pharmacieId: 'pharma-1',
        sessionValid: () => true,
        canWrite: () => true,
        isConnected: () async => true,
        database: () async => db,
      );
      await medicines.saveMedicament(medicament());
    });
    tearDown(() async {
      sync.dispose();
      await db.close();
    });

    test(
      'Activation conserve le stock, réception, correction motivée et refus des modifications obsolètes',
      () async {
        await stock.activate(await current());
        final activated = await current();
        expect(activated.stockTotal, 1000);
        expect(activated.lots!.single.coutBase, 0.5);
        await stock.receive(activated, lot('receipt', 200, 2));
        expect((await current()).stockTotal, 1200);
        await expectLater(
          stock.adjust(activated, 'receipt', 50, 'Casse'),
          throwsStateError,
        );
        expect(
          () => stock.adjust(activated, 'receipt', 0, ''),
          throwsFormatException,
        );
        await stock.adjust(await current(), 'receipt', 50, 'Casse');
        expect((await current()).stockTotal, 1050);
        expect(await stock.movements('pharma-1', 'med-1'), hasLength(4));
        await expectLater(
          medicines.saveMedicament(
            (await current()).copyWith(unites: const UnitesStock()),
            isEdit: true,
          ),
          throwsFormatException,
        );
        final changed = MedicamentModel.fromMap({
          ...(await current()).toMap(),
          'unite_prix': 'comprimes',
        }, 'med-1');
        await expectLater(
          medicines.saveMedicament(changed, isEdit: true),
          throwsStateError,
        );
        await expectLater(
          stock.movements('foreign', 'med-1'),
          throwsStateError,
        );
      },
    );

    test(
      'Vente atomique, historique des coûts, synchronisation et mouvements idempotents',
      () async {
        await stock.activate(await current());
        await stock.receive(await current(), lot('early', 100, 1));
        final sale = vente(items: [line(await current(), 2)]);
        await sales.effectuerVente(sale);
        final before = await current();
        expect(before.stockTotal, 900);
        expect(sale.items.single.prixAchat, 75);
        await sync.sync();
        final remote = MedicamentModel.fromMap(
          (await cloud.doc('pharmacies/pharma-1/medicaments/med-1').get())
              .data()!,
          'med-1',
        );
        expect(remote.stockTotal, 900);
        expect(
          remote.lots!.firstWhere((entry) => entry.id == 'early').quantiteBase,
          0,
        );
        expect(await db.query('sync_queue'), isEmpty);
        expect(
          (await db.query('activites')).every((entry) => entry['synced'] == 1),
          isTrue,
        );
        expect(
          (await cloud
                  .collection('pharmacies/pharma-1/activites')
                  .where('type', isEqualTo: 'mouvement_stock')
                  .get())
              .docs,
          hasLength(4),
        );
        await sales.effectuerVente(sale);
        expect(await db.query('activites'), hasLength(4));
        final history = await sales.getHistoriqueVentes('pharma-1');
        expect(history.single.items.single.lots.map((entry) => entry.numero), [
          'early',
          'Stock initial',
        ]);
        expect(history.single.benefice, 50);
      },
    );

    test(
      'Un conflit ne peut pas réaffecter une vente à un autre lot',
      () async {
        await stock.activate(await current());
        await stock.receive(await current(), lot('early', 100, 1));
        await sync.sync();
        await sales.effectuerVente(vente(items: [line(await current(), 1)]));
        final reference = cloud.doc('pharmacies/pharma-1/medicaments/med-1');
        final remote = MedicamentModel.fromMap(
          (await reference.get()).data()!,
          'med-1',
        );
        final updated = remote.deduireArticle(line(remote, 1), now);
        await reference.set(updated.toMap());
        await expectLater(sync.sync(), throwsStateError);
        final pending = (await sync.pendingOperations()).single;
        await expectLater(
          sync.previewSaleReconciliation(pending.id),
          throwsStateError,
        );
        expect(
          (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
          isEmpty,
        );
        expect(await db.query('ventes'), hasLength(1));
      },
    );

    test(
      'Sauvegarde et restauration conservent lots, allocations et mouvements en attente',
      () async {
        await stock.activate(await current());
        await stock.receive(await current(), lot('early', 100, 1));
        await sales.effectuerVente(vente(items: [line(await current(), 2)]));
        final contents = <String, dynamic>{};
        for (final table in BackupService.tables) {
          contents[table] = await db.query(table);
        }
        final bytes = Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format_version': 1,
              'schema_version': 3,
              'pharmacie_id': 'pharma-1',
              'exported_at': now.toIso8601String(),
              'tables': contents,
            }),
          ),
        );
        final target = await LocalDatabase.open(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );
        try {
          final backup = BackupService(access, database: () async => target);
          await backup.restore(
            await backup.inspect(bytes, '', 'pharma-1'),
            'pharma-1',
          );
          expect(
            MedicamentModel.fromSql(
              (await target.query('medicaments')).single,
            ).stockTotal,
            900,
          );
          expect(
            (await target.query(
              'activites',
            )).every((entry) => entry['synced'] == 0),
            isTrue,
          );
          final restoredSync = SyncService(
            cloud,
            pharmacieId: 'pharma-1',
            sessionValid: () => true,
            canWrite: () => true,
            isConnected: () async => true,
            database: () async => target,
          );
          try {
            await restoredSync.sync();
          } finally {
            restoredSync.dispose();
          }
          expect(await target.query('sync_queue'), isEmpty);
          expect(
            VenteItemModel.fromMap(
              (await target.query('vente_items')).single,
            ).lots,
            hasLength(2),
          );
        } finally {
          await target.close();
        }
      },
    );
  });
}
