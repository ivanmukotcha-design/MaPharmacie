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
import 'package:pharmaflow/local_database/sync_codec.dart';

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

  test(
    'Un conflit ne bloque ni les opérations indépendantes ni leur téléchargement',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      await sales.effectuerVente(vente(id: 'sale-2'));
      await medicines.saveMedicament(medicament(id: 'independent'));
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 2,
      });
      await cloud
          .doc('pharmacies/pharma-1/medicaments/cloud-only')
          .set(medicament(id: 'cloud-only').copyWith(revision: 1).toMap());
      await expectLater(sync.sync(), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(2));
      expect(
        (await cloud.doc('pharmacies/pharma-1/medicaments/independent').get())
            .exists,
        isTrue,
      );
      expect(
        await db.query(
          'medicaments',
          where: 'id = ?',
          whereArgs: ['cloud-only'],
        ),
        hasLength(1),
      );
      expect(
        (await db.query(
          'medicaments',
          where: 'id = ?',
          whereArgs: ['med-1'],
        )).single['synced'],
        0,
      );
      await expectLater(
        sales.effectuerVente(vente(id: 'sale-3')),
        throwsStateError,
      );
    },
  );

  test(
    'Rapprocher deux ventes hors ligne déduit le stock serveur sans perdre ses autres changements',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      await sales.effectuerVente(vente(id: 'sale-2'));
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 2,
        'nom': 'Nom corrigé',
        'unites': const UnitesStock(boites: 7).toMap(),
      });
      await expectLater(sync.sync(), throwsStateError);
      final first = (await sync.pendingOperations()).first;
      final preview = await sync.previewSaleReconciliation(first.id);
      expect(preview.stocks.single.unites.totalBoites, 7);
      await sync.reconcileSale(preview);
      expect(await db.query('sync_queue'), hasLength(1));
      expect((await db.query('medicaments')).single['synced'], 0);
      await expectLater(sync.sync(), throwsStateError);
      final second = (await sync.pendingOperations()).single;
      await sync.reconcileSale(await sync.previewSaleReconciliation(second.id));
      final local = MedicamentModel.fromSql(
        (await db.query('medicaments')).single,
      );
      expect(local.unites.totalBoites, 3);
      expect(local.nom, 'Nom corrigé');
      expect((await db.query('medicaments')).single['synced'], 1);
      expect(await db.query('sync_queue'), isEmpty);
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        hasLength(2),
      );
    },
  );

  test(
    'Un stock changé après prévisualisation ne peut pas être confirmé',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 2,
      });
      await expectLater(sync.sync(), throwsStateError);
      final preview = await sync.previewSaleReconciliation(
        (await sync.pendingOperations()).single.id,
      );
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 3,
      });
      await expectLater(sync.reconcileSale(preview), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(1));
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        isEmpty,
      );
    },
  );

  test(
    'Stock insuffisant ou conditionnement modifié : aucun rapprochement automatique',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      final reference = cloud.doc('pharmacies/pharma-1/medicaments/med-1');
      await reference.update({
        'revision': 2,
        'unites': const UnitesStock(boites: 1).toMap(),
      });
      await expectLater(sync.sync(), throwsStateError);
      final id = (await sync.pendingOperations()).single.id;
      await expectLater(sync.previewSaleReconciliation(id), throwsStateError);
      await reference.update({
        'unites': const UnitesStock(boites: 10, cartonsParBoite: 12).toMap(),
      });
      await expectLater(sync.previewSaleReconciliation(id), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(1));
    },
  );

  test(
    'Une correction de fiche dépendante interdit le rapprochement isolé de la vente',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      final local = MedicamentModel.fromSql(
        (await db.query('medicaments')).single,
      );
      await medicines.saveMedicament(
        local.copyWith(unites: const UnitesStock(boites: 20)),
        isEdit: true,
      );
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 2,
      });
      await expectLater(sync.sync(), throwsStateError);
      await expectLater(
        sync.previewSaleReconciliation(
          (await sync.pendingOperations()).first.id,
        ),
        throwsStateError,
      );
      expect(await db.query('sync_queue'), hasLength(2));
    },
  );

  test(
    'Le reçu durable empêche le rejeu d’une ancienne modification après une vente',
    () async {
      await medicines.saveMedicament(medicament());
      final original = Map<String, Object?>.from(
        (await db.query('sync_queue')).single,
      );
      await sync.sync();
      await sales.effectuerVente(vente());
      await sync.sync();
      await db.insert('sync_queue', original);
      await sync.sync();
      final remote = await cloud
          .doc('pharmacies/pharma-1/medicaments/med-1')
          .get();
      expect(
        UnitesStock.fromMap(
          Map<String, dynamic>.from(remote.data()!['unites']),
        ).totalBoites,
        8,
      );
      expect(remote.data()!['revision'], 2);
      expect(await db.query('sync_queue'), isEmpty);
    },
  );

  test(
    'Un identifiant d’opération réutilisé avec un autre contenu est refusé',
    () async {
      await medicines.saveMedicament(medicament());
      final original = Map<String, Object?>.from(
        (await db.query('sync_queue')).single,
      );
      await sync.sync();
      final data = SyncCodec.decode(original['data'] as String);
      data['document']['nom'] = 'Contenu différent';
      original['data'] = SyncCodec.encode(data);
      await db.insert('sync_queue', original);
      await expectLater(sync.sync(), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(1));
      expect(
        (await cloud.doc('pharmacies/pharma-1/medicaments/med-1').get())
            .data()!['nom'],
        medicament().nom,
      );
    },
  );

  test(
    'Un changement de session interdit de confirmer un rapprochement',
    () async {
      await medicines.saveMedicament(medicament());
      await sync.sync();
      await sales.effectuerVente(vente());
      final preview = await sync.previewSaleReconciliation(
        (await sync.pendingOperations()).single.id,
      );
      signedIn = false;
      await expectLater(sync.reconcileSale(preview), throwsStateError);
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        isEmpty,
      );
    },
  );

  test(
    'Une opération legacy reste visible et ne donne pas un faux succès',
    () async {
      await medicines.saveMedicament(medicament());
      await db.update('sync_queue', {
        'operation': 'legacy',
        'data': '{ancien format}',
        'last_error': 'Ancienne opération : contactez le support.',
      });
      await expectLater(sync.sync(), throwsStateError);
      expect(sync.status.error, isNotNull);
      expect(await db.query('sync_queue'), hasLength(1));
    },
  );

  test(
    'Un conflit protège aussi les produits des opérations dépendantes transitives',
    () async {
      await medicines.saveMedicament(medicament());
      await medicines.saveMedicament(medicament(id: 'med-2'));
      await sync.sync();
      await sales.effectuerVente(vente());
      await sales.effectuerVente(
        vente(
          id: 'sale-linked',
          items: [
            venteItem(),
            venteItem(id: 'med-2'),
          ],
        ),
      );
      await sales.effectuerVente(
        vente(
          id: 'sale-dependent',
          items: [venteItem(id: 'med-2')],
        ),
      );
      await cloud.doc('pharmacies/pharma-1/medicaments/med-1').update({
        'revision': 2,
      });
      await cloud.doc('pharmacies/pharma-1/medicaments/med-2').update({
        'revision': 2,
      });
      await expectLater(sync.sync(), throwsStateError);
      expect(await db.query('sync_queue'), hasLength(3));
      await expectLater(
        sales.effectuerVente(
          vente(
            id: 'blocked-sale',
            items: [venteItem(id: 'med-2')],
          ),
        ),
        throwsStateError,
      );
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        isEmpty,
      );
    },
  );
}
