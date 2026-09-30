import 'dart:convert';
import 'dart:typed_data';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/medicament_repository.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/repositories/vente_repository.dart';
import 'package:pharmaflow/services/backup_cipher.dart';
import 'package:pharmaflow/services/backup_service.dart';
import 'package:pharmaflow/services/sync_service.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  final access = RepositoryAccess((_, __) {});
  const password = 'une longue phrase privée';
  late Database source;
  late Database target;
  late BackupService backup;
  late Map<String, dynamic> contents;
  late FakeFirebaseFirestore cloud;

  Uint8List encode(Map<String, dynamic> data) =>
      Uint8List.fromList(utf8.encode(jsonEncode(data)));

  setUp(() async {
    source = await LocalDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    target = await LocalDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    cloud = FakeFirebaseFirestore();
    backup = BackupService(access, database: () async => target);
    await MedicamentRepository(
      access,
      database: () async => source,
    ).saveMedicament(medicament());
    await VenteRepository(
      access,
      database: () async => source,
    ).effectuerVente(vente());
    contents = {
      'format_version': 1,
      'schema_version': 2,
      'pharmacie_id': 'pharma-1',
      'exported_at': DateTime(2026, 9, 30).toIso8601String(),
      'tables': {
        for (final table in BackupService.tables)
          table: (await source.query(
            table,
          )).map((row) => Map<String, dynamic>.from(row)).toList(),
      },
    };
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  SyncService synchronizer(Database db) => SyncService(
    cloud,
    pharmacieId: 'pharma-1',
    sessionValid: () => true,
    canWrite: () => true,
    isConnected: () async => true,
    database: () async => db,
  );

  test(
    'Chiffrement authentifié : ouverture, mauvaise phrase, altération et aléa',
    () async {
      await MedicamentRepository(
        access,
        database: () async => source,
      ).saveMedicament(medicament(id: 'foreign', pharmacieId: 'pharma-2'));
      final sourceBackup = BackupService(access, database: () async => source);
      final encrypted = await sourceBackup.create('pharma-1', password);
      expect(utf8.decode(encrypted), isNot(contains('Produit med-1')));
      expect(utf8.decode(encrypted), isNot(contains('pharma-1')));
      final snapshot = await backup.inspect(encrypted, password, 'pharma-1');
      expect(snapshot.encrypted, isTrue);
      expect(snapshot.count('medicaments'), 1);
      expect(snapshot.count('sync_queue'), 2);
      await backup.restore(snapshot, 'pharma-1');
      expect(await target.query('medicaments'), hasLength(1));
      await expectLater(
        backup.inspect(encrypted, 'mauvaise phrase secrète', 'pharma-1'),
        throwsFormatException,
      );
      final envelope = BackupCipher.readEnvelope(encrypted);
      final cipherText = base64Decode(envelope['ciphertext'] as String);
      cipherText[0] ^= 1;
      envelope['ciphertext'] = base64Encode(cipherText);
      await expectLater(
        backup.inspect(encode(envelope), password, 'pharma-1'),
        throwsFormatException,
      );
      final second = await sourceBackup.create('pharma-1', password);
      expect(
        BackupCipher.readEnvelope(second)['salt'],
        isNot(BackupCipher.readEnvelope(encrypted)['salt']),
      );
      expect(
        BackupCipher.readEnvelope(second)['nonce'],
        isNot(BackupCipher.readEnvelope(encrypted)['nonce']),
      );
      expect(await target.query('ventes'), hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Refuser une phrase trop courte et un coût cryptographique modifié',
    () async {
      await expectLater(
        BackupCipher.encrypt('{}', 'court'),
        throwsFormatException,
      );
      await expectLater(
        BackupCipher.decrypt(
          encode({
            'format': 'pharmaflow-backup',
            'version': 2,
            'cipher': 'aes-256-gcm',
            'kdf': 'pbkdf2-sha256',
            'iterations': 999999999,
            'ciphertext': '',
          }),
          password,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Restauration puis rejeu de la même copie ne doublent ni vente ni déduction',
    () async {
      final snapshot = await backup.inspect(encode(contents), '', 'pharma-1');
      final firstSync = synchronizer(source);
      final secondSync = synchronizer(target);
      addTearDown(firstSync.dispose);
      addTearDown(secondSync.dispose);
      await firstSync.sync();
      await backup.restore(snapshot, 'pharma-1');
      expect(await target.query('sync_queue'), hasLength(2));
      await secondSync.sync();
      await backup.restore(snapshot, 'pharma-1');
      await secondSync.sync();
      expect(await target.query('ventes'), hasLength(1));
      expect(await target.query('vente_items'), hasLength(1));
      expect(await target.query('sync_queue'), isEmpty);
      expect(
        MedicamentModel.fromSql(
          (await target.query('medicaments')).single,
        ).unites.totalBoites,
        8,
      );
      expect(
        (await cloud.collection('pharmacies/pharma-1/ventes').get()).docs,
        hasLength(1),
      );
      final remote = await cloud
          .doc('pharmacies/pharma-1/medicaments/med-1')
          .get();
      expect(
        UnitesStock.fromMap(
          Map<String, dynamic>.from(remote.data()!['unites']),
        ).totalBoites,
        8,
      );
    },
  );

  test(
    'Une copie ancienne ne remplace pas les fiches existantes sans opération en attente',
    () async {
      final sync = synchronizer(source);
      addTearDown(sync.dispose);
      await sync.sync();
      for (final table in BackupService.tables) {
        contents['tables'][table] = (await source.query(
          table,
        )).map((row) => Map<String, dynamic>.from(row)).toList();
      }
      final current = medicament().copyWith(
        unites: const UnitesStock(boites: 50),
        revision: 4,
      );
      await target.insert('medicaments', current.toSql(synced: true));
      final snapshot = await backup.inspect(encode(contents), '', 'pharma-1');
      await backup.restore(snapshot, 'pharma-1');
      expect(
        MedicamentModel.fromSql(
          (await target.query('medicaments')).single,
        ).unites.totalBoites,
        50,
      );
      expect(await target.query('sync_queue'), isEmpty);
    },
  );

  test(
    'Les opérations locales existantes empêchent la restauration sans être effacées',
    () async {
      await MedicamentRepository(
        access,
        database: () async => target,
      ).saveMedicament(medicament(id: 'local'));
      final before = await target.query('sync_queue');
      final snapshot = await backup.inspect(encode(contents), '', 'pharma-1');
      await expectLater(backup.restore(snapshot, 'pharma-1'), throwsStateError);
      expect(await target.query('sync_queue'), before);
      expect((await target.query('medicaments')).single['id'], 'local');
    },
  );

  test(
    'Isolation : autre compte, lignes étrangères et identifiant local occupé refusés',
    () async {
      await expectLater(
        backup.inspect(encode(contents), '', 'pharma-2'),
        throwsFormatException,
      );
      final snapshot = await backup.inspect(encode(contents), '', 'pharma-1');
      await target.insert(
        'medicaments',
        medicament(pharmacieId: 'pharma-2').toSql(synced: true),
      );
      await expectLater(
        backup.restore(snapshot, 'pharma-1'),
        throwsFormatException,
      );
      expect(
        (await target.query('medicaments')).single['pharmacie_id'],
        'pharma-2',
      );
      expect(await target.query('ventes'), isEmpty);
      contents['tables']['medicaments'][0]['pharmacie_id'] = 'pharma-2';
      await expectLater(
        backup.inspect(encode(contents), '', 'pharma-1'),
        throwsFormatException,
      );
    },
  );

  test(
    'Une erreur tardive annule toute la transaction de restauration',
    () async {
      contents['tables']['ventes'][0]['colonne_inconnue'] = 'erreur';
      final snapshot = await backup.inspect(encode(contents), '', 'pharma-1');
      await expectLater(
        backup.restore(snapshot, 'pharma-1'),
        throwsFormatException,
      );
      expect(await target.query('medicaments'), isEmpty);
      expect(await target.query('ventes'), isEmpty);
      expect(await target.query('sync_queue'), isEmpty);
    },
  );

  test(
    'Les tables absentes, articles orphelins et totaux altérés sont rejetés',
    () async {
      final original = jsonEncode(contents);
      contents['tables'].remove('activites');
      await expectLater(
        backup.inspect(encode(contents), '', 'pharma-1'),
        throwsFormatException,
      );
      contents = Map<String, dynamic>.from(jsonDecode(original) as Map);
      contents['tables']['vente_items'][0]['vente_id'] = 'absente';
      await expectLater(
        backup.inspect(encode(contents), '', 'pharma-1'),
        throwsFormatException,
      );
      contents = Map<String, dynamic>.from(jsonDecode(original) as Map);
      contents['tables']['ventes'][0]['total_ttc'] = 999999;
      await expectLater(
        backup.inspect(encode(contents), '', 'pharma-1'),
        throwsFormatException,
      );
    },
  );

  test(
    'Une révocation en fin de restauration provoque un rollback complet',
    () async {
      final snapshot = await backup.inspect(encode(contents), '', 'pharma-1');
      var checks = 0;
      final guarded = BackupService(
        RepositoryAccess((owner, write) {
          checks++;
          if (checks >= 3) throw StateError('Session changée');
        }),
        database: () async => target,
      );
      await expectLater(
        guarded.restore(snapshot, 'pharma-1'),
        throwsStateError,
      );
      expect(await target.query('medicaments'), isEmpty);
      expect(await target.query('sync_queue'), isEmpty);
    },
  );
}
