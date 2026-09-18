import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/fournisseur_repository.dart';
import 'package:pharmaflow/repositories/medicament_repository.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/repositories/vente_repository.dart';
import 'package:pharmaflow/services/sync_service.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late FakeFirebaseFirestore cloud;
  late SyncService sync;
  late MedicamentRepository medicines;
  late VenteRepository sales;
  late bool online;
  late bool signedIn;
  late bool writable;
  final access = RepositoryAccess((_, __) {});

  setUp(() async {
    db = await LocalDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    cloud = FakeFirebaseFirestore();
    online = true;
    signedIn = true;
    writable = true;
    sync = SyncService(
      cloud,
      pharmacieId: 'pharma-1',
      sessionValid: () => signedIn,
      canWrite: () => writable,
      isConnected: () async => online,
      database: () async => db,
    );
    medicines = MedicamentRepository(access, database: () async => db);
    sales = VenteRepository(access, database: () async => db);
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
  });

  test(
    'Hors ligne, conserver la file puis envoyer les données complètes',
    () async {
      await medicines.saveMedicament(medicament());
      online = false;
      await expectLater(sync.sync(), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(1));
      expect(
        (await cloud.collection('pharmacies/pharma-1/medicaments').get()).docs,
        isEmpty,
      );
      online = true;
      await sync.sync();
      final remote = await cloud
          .doc('pharmacies/pharma-1/medicaments/med-1')
          .get();
      expect(remote.data()!['nom'], medicament().nom);
      expect(remote.data()!['prix_achat'], 50);
      expect(remote.data()!['unites']['boites'], 10);
      expect(remote.data()!['revision'], 1);
      expect(await db.query('sync_queue'), isEmpty);
      expect((await db.query('medicaments')).single['synced'], 1);
    },
  );

  test(
    'Vente et stock cloud atomiques, reprise idempotente après commit',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      final operation = Map<String, Object?>.from(
        (await db.query('sync_queue')).single,
      );
      await sync.sync();
      await db.insert('sync_queue', operation);
      await db.update('ventes', {'synced': 0});
      await db.update('medicaments', {'synced': 0});
      await sync.sync();
      final stock = await cloud
          .doc('pharmacies/pharma-1/medicaments/med-1')
          .get();
      expect(
        UnitesStock.fromMap(
          Map<String, dynamic>.from(stock.data()!['unites']),
        ).totalBoites,
        8,
      );
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        hasLength(1),
      );
      expect((await db.query('ventes')).single['synced'], 1);
      expect(await db.query('sync_queue'), isEmpty);
    },
  );

  test(
    'Un autre appareil retrouve médicaments, fournisseurs et articles de vente',
    () async {
      await medicines.saveMedicament(medicament());
      await FournisseurRepository(
        access,
        database: () async => db,
      ).saveFournisseur(
        FournisseurModel(
          id: 'supplier-1',
          pharmacieId: 'pharma-1',
          nom: 'Grossiste',
          telephone: '123',
          email: '',
          adresse: 'Adresse',
          createdAt: DateTime(2025),
        ),
      );
      await sales.effectuerVente(vente());
      await sync.sync();
      final secondDb = await LocalDatabase.open(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final second = SyncService(
        cloud,
        pharmacieId: 'pharma-1',
        sessionValid: () => true,
        canWrite: () => true,
        isConnected: () async => true,
        database: () async => secondDb,
      );
      try {
        await second.sync();
        expect(
          (await secondDb.query('fournisseurs')).single['nom'],
          'Grossiste',
        );
        expect((await secondDb.query('vente_items')).single['quantite'], 2);
        expect((await secondDb.query('medicaments')).single['synced'], 1);
        expect(await secondDb.query('sync_queue'), isEmpty);
      } finally {
        second.dispose();
        await secondDb.close();
      }
    },
  );

  test(
    'Conflit distant : aucun écrasement, vente non envoyée, file conservée',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 2,
        'nom': 'Autre appareil',
      });
      await expectLater(sync.sync(), throwsStateError);
      expect((await db.query('sync_queue')).single['attempts'], 1);
      expect(
        (await db.query('sync_queue')).single['last_error'],
        contains('Conflit'),
      );
      expect((await db.query('medicaments')).single['nom'], medicament().nom);
      expect((await db.query('medicaments')).single['synced'], 0);
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        isEmpty,
      );
    },
  );

  test(
    'Une session ne traite jamais les opérations des autres pharmacies',
    () async {
      await medicines.saveMedicament(
        medicament(id: 'other', pharmacieId: 'pharma-2'),
      );
      await medicines.saveMedicament(medicament());
      await sync.sync();
      expect((await db.query('sync_queue')).single['pharmacie_id'], 'pharma-2');
      expect(
        (await cloud.collection('pharmacies/pharma-2/medicaments').get()).docs,
        isEmpty,
      );
      signedIn = false;
      await expectLater(sync.sync(), throwsStateError);
    },
  );

  test(
    'Un accès en écriture révoqué conserve ses opérations sans les envoyer',
    () async {
      await medicines.saveMedicament(medicament());
      writable = false;
      await expectLater(sync.sync(), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(1));
      expect(
        (await cloud.collection('pharmacies/pharma-1/medicaments').get()).docs,
        isEmpty,
      );
    },
  );

  test(
    'Deux demandes de synchronisation partagent la même exécution',
    () async {
      await medicines.saveMedicament(medicament());
      final first = sync.sync();
      final second = sync.sync();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(await db.query('sync_queue'), isEmpty);
      expect(
        (await cloud.doc('pharmacies/pharma-1/medicaments/med-1').get())
            .data()!['revision'],
        1,
      );
    },
  );
}
