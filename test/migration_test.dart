import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmaflow/local_database/local_database.dart';

void main() {
  sqfliteFfiInit();
  test(
    'Migration v1 conserve le stock et met les anciennes opérations en quarantaine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pharmaflow_migration_',
      );
      final path = '${directory.path}/migration.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE medicaments (id TEXT PRIMARY KEY, nom TEXT, cartons INTEGER, boites INTEGER, plaquettes INTEGER, comprimes INTEGER, flacons INTEGER)',
            );
            await db.execute(
              'CREATE TABLE fournisseurs (id TEXT PRIMARY KEY, nom TEXT)',
            );
            await db.execute(
              'CREATE TABLE sync_queue (id INTEGER PRIMARY KEY, collection TEXT, doc_id TEXT, operation TEXT, data TEXT, created_at TEXT, attempts INTEGER)',
            );
            await db.insert('medicaments', {
              'id': 'legacy',
              'nom': 'Sirop',
              'cartons': 0,
              'boites': 0,
              'plaquettes': 0,
              'comprimes': 0,
              'flacons': 6,
            });
            await db.insert('sync_queue', {
              'id': 1,
              'collection': 'pharmacies/pharma-1/medicaments',
              'doc_id': 'legacy',
              'operation': 'set',
              'data': '{nom: Sirop}',
              'attempts': 5,
            });
          },
        ),
      );
      await legacy.close();
      final migrated = await LocalDatabase.open(
        path,
        factory: databaseFactoryFfi,
      );
      try {
        expect(await migrated.getVersion(), 2);
        final medicine = (await migrated.query('medicaments')).single;
        expect(medicine['flacons'], 6);
        expect(medicine['unite_prix'], 'flacon');
        expect(medicine['prix_achat'], isNull);
        final operation = (await migrated.query('sync_queue')).single;
        expect(operation['operation'], 'legacy');
        expect(operation['pharmacie_id'], 'pharma-1');
        expect(operation['operation_id'], isNotEmpty);
        expect(operation['data'], '{nom: Sirop}');
        expect(operation['last_error'], isNotEmpty);
        expect(
          await LocalDatabase.getPendingSync('pharma-1', executor: migrated),
          hasLength(1),
        );
      } finally {
        await migrated.close();
        await databaseFactoryFfi.deleteDatabase(path);
        await directory.delete();
      }
    },
  );
}
