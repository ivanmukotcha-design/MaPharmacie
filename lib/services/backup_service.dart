import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../local_database/local_database.dart';
import '../local_database/sync_codec.dart';
import '../models/models.dart';
import '../repositories/repository_access.dart';
import 'backup_cipher.dart';
import 'sync_operation.dart';

Future<Uint8List> _encryptBackup((String, String) input) =>
    BackupCipher.encrypt(input.$1, input.$2);
Future<String> _decryptBackup((Uint8List, String) input) =>
    BackupCipher.decrypt(input.$1, input.$2);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(repositoryAccessProvider)),
);

class BackupSnapshot {
  final String _json;
  final bool encrypted;
  BackupSnapshot._(this._json, this.encrypted);
  Map<String, dynamic> get _data =>
      Map<String, dynamic>.from(jsonDecode(_json) as Map);
  String get owner => _data['pharmacie_id'] as String;
  DateTime get date => DateTime.parse(_data['exported_at'] as String);
  int count(String table) => (_data['tables'][table] as List).length;
}

class BackupService {
  final RepositoryAccess _access;
  final Future<Database> Function() _database;
  static const tables = [
    'medicaments',
    'fournisseurs',
    'ventes',
    'vente_items',
    'activites',
    'sync_queue',
  ];

  BackupService(this._access, {Future<Database> Function()? database})
    : _database = database ?? (() => LocalDatabase.database);

  Future<Uint8List> create(String owner, String password) async {
    _access.read(owner);
    final db = await _database();
    final data = await db.transaction((transaction) async {
      _access.read(owner);
      final contents = <String, dynamic>{};
      for (final table in tables.where((table) => table != 'vente_items')) {
        contents[table] = await transaction.query(
          table,
          where: 'pharmacie_id = ?',
          whereArgs: [owner],
          orderBy: 'id ASC',
        );
      }
      contents['vente_items'] = await transaction.rawQuery(
        'SELECT items.* FROM vente_items items JOIN ventes ON ventes.id = items.vente_id WHERE ventes.pharmacie_id = ? ORDER BY items.id',
        [owner],
      );
      _access.read(owner);
      return {
        'format_version': 1,
        'schema_version': 3,
        'pharmacie_id': owner,
        'exported_at': DateTime.now().toIso8601String(),
        'tables': contents,
      };
    });
    final contents = jsonEncode(data);
    final encrypted = await compute(_encryptBackup, (contents, password));
    _access.read(owner);
    return encrypted;
  }

  Future<BackupSnapshot> inspect(
    Uint8List bytes,
    String password,
    String owner,
  ) async {
    _access.read(owner);
    final envelope = BackupCipher.readEnvelope(bytes);
    final encrypted = envelope.containsKey('ciphertext');
    final contents = encrypted
        ? await compute(_decryptBackup, (bytes, password))
        : utf8.decode(bytes);
    _access.read(owner);
    try {
      final data = Map<String, dynamic>.from(jsonDecode(contents) as Map);
      _validate(data, owner);
      return BackupSnapshot._(contents, encrypted);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'La sauvegarde contient des données invalides. Aucune donnée n’a été modifiée.',
      );
    }
  }

  void _validate(Map<String, dynamic> data, String owner) {
    if (data['format_version'] != 1 ||
        ![2, 3].contains(data['schema_version'])) {
      throw const FormatException('Version de sauvegarde non prise en charge.');
    }
    if (data['pharmacie_id'] != owner) {
      throw const FormatException(
        'Cette sauvegarde appartient à une autre pharmacie. Connectez-vous au compte correspondant.',
      );
    }
    DateTime.parse(data['exported_at'] as String);
    final contents = Map<String, dynamic>.from(data['tables'] as Map);
    if (contents.length != tables.length ||
        !tables.every(contents.containsKey)) {
      throw const FormatException('La sauvegarde est incomplète.');
    }
    final ids = <String, Set<Object>>{};
    var totalRows = 0;
    for (final table in tables) {
      final rows = contents[table] as List;
      totalRows += rows.length;
      if (totalRows > 100000) {
        throw const FormatException(
          'Trop de lignes dans cette sauvegarde. Contactez le support.',
        );
      }
      ids[table] = <Object>{};
      for (final value in rows) {
        final row = Map<String, dynamic>.from(value as Map);
        final id = row['id'];
        if (id == null ||
            (table == 'sync_queue'
                ? id is! int || id <= 0
                : id is! String || id.isEmpty || id.contains('/')) ||
            !ids[table]!.add(id)) {
          throw const FormatException(
            'Identifiant de sauvegarde invalide ou en double.',
          );
        }
        if (table != 'vente_items' && row['pharmacie_id'] != owner) {
          throw const FormatException(
            'Des lignes appartiennent à une autre pharmacie.',
          );
        }
        if (table != 'vente_items' &&
            table != 'sync_queue' &&
            ![0, 1].contains(row['synced'])) {
          throw const FormatException('État de synchronisation invalide.');
        }
        if (table == 'medicaments') {
          final med = MedicamentModel.fromSql(row)..validate();
          if (med.revision < 0 || ![0, 1].contains(row['est_actif'])) {
            throw const FormatException('Fiche médicament invalide.');
          }
        }
        if (table == 'fournisseurs') {
          final supplier = FournisseurModel.fromSql(row);
          if (supplier.nom.trim().isEmpty ||
              supplier.revision < 0 ||
              ![0, 1].contains(row['est_actif'])) {
            throw const FormatException('Fiche fournisseur invalide.');
          }
        }
      }
    }
    final items = (contents['vente_items'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    for (final item in items) {
      if (!ids['ventes']!.contains(item['vente_id'])) {
        throw const FormatException('Article sans vente correspondante.');
      }
    }
    final sales = <String, VenteModel>{};
    for (final value in contents['ventes'] as List) {
      final row = Map<String, dynamic>.from(value as Map);
      final sale = VenteModel.fromSql(
        row,
        items.where((item) => item['vente_id'] == row['id']).toList(),
      );
      _validateSale(sale);
      sales[sale.id] = sale;
    }
    final operations = <String>{};
    final affected = <String>{};
    for (final value in contents['sync_queue'] as List) {
      final operation = SyncOperation(Map<String, dynamic>.from(value as Map))
        ..validate(owner);
      if (!operations.add(operation.operationId) ||
          !ids[operation.table]!.contains(operation.documentId)) {
        throw const FormatException(
          'Opération sans document correspondant ou en double.',
        );
      }
      affected.addAll(operation.affected);
      for (final activity in operation.activities) {
        final matching = (contents['activites'] as List).where(
          (row) => row['id'] == activity['id'],
        );
        if (matching.length != 1 ||
            SyncCodec.encode(
                  ActiviteModel.fromSql(
                    Map<String, dynamic>.from(matching.single as Map),
                  ).toMap(),
                ) !=
                SyncCodec.encode(
                  Map<String, dynamic>.from(activity['document'] as Map),
                )) {
          throw const FormatException(
            'Mouvement absent ou différent de son opération.',
          );
        }
      }
      if (operation.kind == 'legacy') continue;
      if (operation.kind == 'sale') {
        final sale = VenteModel.fromMap(
          operation.document,
          operation.documentId,
        );
        _validateSale(sale);
        if (!_sameSale(sale, sales[sale.id]!) ||
            operation.stockUpdates.length != sale.items.length ||
            operation.stockUpdates.map((entry) => entry['id']).toSet().length !=
                sale.items.length) {
          throw const FormatException(
            'Une opération ne correspond pas à sa vente.',
          );
        }
      } else {
        final revision = operation.data['expected_revision'];
        if (revision is! int ||
            revision < 0 ||
            operation.document['revision'] != revision + 1) {
          throw const FormatException('Révision de synchronisation invalide.');
        }
        if (operation.table == 'medicaments') {
          MedicamentModel.fromMap(
            operation.document,
            operation.documentId,
          ).validate();
        } else if (FournisseurModel.fromMap(
          operation.document,
          operation.documentId,
        ).nom.trim().isEmpty) {
          throw const FormatException('Fournisseur en attente invalide.');
        }
      }
      for (final update in operation.stockUpdates) {
        if (!ids['medicaments']!.contains(update['id']) ||
            update['expected_revision'] is! int ||
            update['expected_revision'] < 0 ||
            update['document']['revision'] != update['expected_revision'] + 1 ||
            !sales[operation.documentId]!.items.any(
              (item) => item.medicamentId == update['id'],
            )) {
          throw const FormatException('Mouvement de stock invalide.');
        }
        MedicamentModel.fromMap(
          Map<String, dynamic>.from(update['document'] as Map),
          update['id'] as String,
        ).validate();
      }
    }
    for (final table in ['medicaments', 'fournisseurs', 'ventes']) {
      for (final row in contents[table] as List) {
        if (row['synced'] == 0 &&
            !affected.contains('*') &&
            !affected.contains('$table/${row['id']}')) {
          throw const FormatException(
            'La sauvegarde contient des modifications sans opération de synchronisation. Contactez le support.',
          );
        }
      }
    }
  }

  void _validateSale(VenteModel sale) {
    if (!['detail', 'gros'].contains(sale.typeVente) ||
        sale.items.isEmpty ||
        sale.items.length > 100 ||
        sale.items.map((item) => item.medicamentId).toSet().length !=
            sale.items.length) {
      throw const FormatException('Vente invalide.');
    }
    var total = 0.0;
    var margin = 0.0;
    for (final item in sale.items) {
      if (item.medicamentId.isEmpty ||
          item.medicamentId.contains('/') ||
          item.quantite <= 0 ||
          ![
            'carton',
            'boite',
            'plaquette',
            'comprimes',
            'flacon',
          ].contains(item.unite) ||
          [
            item.prixUnitaire,
            item.prixAchat,
            item.sousTotal,
          ].any((price) => !price.isFinite || price < 0) ||
          (item.sousTotal - item.quantite * item.prixUnitaire).abs() >
              0.000001) {
        throw const FormatException('Article de vente invalide.');
      }
      total += item.sousTotal;
      for (final allocation in item.lots) {
        allocation.validate();
      }
      if (item.lots.isNotEmpty &&
          (item.lots.map((entry) => entry.lotId).toSet().length !=
                  item.lots.length ||
              (item.lots.fold(0.0, (total, entry) => total + entry.coutTotal) -
                          item.prixAchat * item.quantite)
                      .abs() >
                  0.000001)) {
        throw const FormatException('Coûts des lots vendus incohérents.');
      }
      margin += item.beneficeItem;
    }
    if (![
          sale.totalHT,
          sale.totalTTC,
          sale.benefice,
          total,
          margin,
        ].every((value) => value.isFinite) ||
        (sale.totalHT - total).abs() > 0.000001 ||
        (sale.totalTTC - total).abs() > 0.000001 ||
        (sale.benefice - margin).abs() > 0.000001) {
      throw const FormatException('Totaux de vente invalides.');
    }
  }

  Future<void> restore(BackupSnapshot snapshot, String owner) async {
    _access.write(owner);
    final data = snapshot._data;
    _validate(data, owner);
    final contents = data['tables'] as Map;
    final db = await _database();
    await db.transaction((transaction) async {
      _access.write(owner);
      if ((await LocalDatabase.getPendingSync(
        owner,
        executor: transaction,
      )).isNotEmpty) {
        throw StateError(
          'Cet appareil a déjà des opérations en attente. Synchronisez-les ou faites-les rapprocher avant de restaurer une copie.',
        );
      }
      final queue =
          (contents['sync_queue'] as List)
              .map(
                (row) => SyncOperation(Map<String, dynamic>.from(row as Map)),
              )
              .toList()
            ..sort((first, second) => first.id.compareTo(second.id));
      final affected = queue.expand((operation) => operation.affected).toSet();
      final newSales = <String>{};
      for (final table in tables.where((table) => table != 'sync_queue')) {
        final columns = (await transaction.rawQuery(
          'PRAGMA table_info($table)',
        )).map((column) => column['name'] as String).toSet();
        for (final value in contents[table] as List) {
          final row = Map<String, dynamic>.from(value as Map);
          if (!columns.containsAll(row.keys)) {
            throw const FormatException('Colonnes de sauvegarde inconnues.');
          }
          if (table == 'vente_items') {
            if (newSales.contains(row['vente_id'])) {
              await transaction.insert(table, row);
            }
            continue;
          }
          final existing = await transaction.query(
            table,
            where: 'id = ?',
            whereArgs: [row['id']],
          );
          if (existing.isNotEmpty && existing.single['pharmacie_id'] != owner) {
            throw const FormatException(
              'Un identifiant appartient déjà à une autre pharmacie. Restauration annulée.',
            );
          }
          if (existing.isNotEmpty && existing.single['synced'] == 0) {
            throw StateError(
              'Une modification locale non synchronisée doit être vérifiée avant restauration.',
            );
          }
          if (table == 'ventes' && existing.isNotEmpty) {
            final oldItems = await transaction.query(
              'vente_items',
              where: 'vente_id = ?',
              whereArgs: [row['id']],
            );
            final oldSale = VenteModel.fromSql(existing.single, oldItems);
            final backupItems = (contents['vente_items'] as List)
                .where((item) => item['vente_id'] == row['id'])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            final restoredSale = VenteModel.fromSql(row, backupItems);
            if (!_sameSale(oldSale, restoredSale)) {
              throw const FormatException(
                'Une vente existante diffère de la sauvegarde. Aucune donnée n’a été remplacée.',
              );
            }
          }
          final pending =
              affected.contains('*') ||
              affected.contains('$table/${row['id']}');
          if (existing.isEmpty) {
            if (table == 'ventes') newSales.add(row['id'] as String);
            await transaction.insert(table, {
              ...row,
              'synced': pending ? 0 : 1,
            });
          } else if (pending &&
              ['medicaments', 'fournisseurs'].contains(table)) {
            if (table == 'medicaments' &&
                existing.single['lots_json'] != null &&
                row['lots_json'] == null) {
              throw const FormatException(
                'Cette sauvegarde ne suit pas les lots déjà activés sur cet appareil.',
              );
            }
            await transaction.update(
              table,
              {...row, 'synced': 0},
              where: 'id = ? AND pharmacie_id = ?',
              whereArgs: [row['id'], owner],
            );
          }
        }
      }
      for (final operation in queue) {
        final row = Map<String, dynamic>.from(operation.row)..remove('id');
        row['last_error'] =
            'Données restaurées : synchronisez et vérifiez les opérations avant de reprendre.';
        await transaction.insert('sync_queue', row);
      }
      _access.write(owner);
    });
    LocalDatabase.notifyChanged();
  }

  bool _sameSale(VenteModel first, VenteModel second) {
    Map<String, dynamic> sorted(VenteModel sale) {
      final items = sale.items.toList()
        ..sort(
          (first, second) => first.medicamentId.compareTo(second.medicamentId),
        );
      return {
        ...sale.toMap(),
        'items': items.map((item) => item.toMap()).toList(),
      };
    }

    return SyncCodec.encode(sorted(first)) == SyncCodec.encode(sorted(second));
  }
}
