import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../local_database/local_database.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import 'repository_access.dart';

final medicamentRepositoryProvider = Provider<MedicamentRepository>((ref) {
  final sync = ref.watch(syncServiceProvider);
  return MedicamentRepository(
    RepositoryAccess.forRef(ref),
    onChanged: sync.scheduleSync,
  );
});

class MedicamentRepository {
  final RepositoryAccess _access;
  final Future<Database> Function() _database;
  final void Function()? _onChanged;

  MedicamentRepository(
    this._access, {
    Future<Database> Function()? database,
    void Function()? onChanged,
  }) : _database = database ?? (() => LocalDatabase.database),
       _onChanged = onChanged;

  Future<void> saveMedicament(
    MedicamentModel medicament, {
    bool isEdit = false,
  }) async {
    _access.write(medicament.pharmacieId);
    medicament.validate();
    final db = await _database();
    await db.transaction((transaction) async {
      _access.write(medicament.pharmacieId);
      final rows = await transaction.query(
        'medicaments',
        where: 'id = ? AND pharmacie_id = ?',
        whereArgs: [medicament.id, medicament.pharmacieId],
      );
      if (isEdit && rows.isEmpty) throw StateError('Médicament introuvable.');
      if (!isEdit && rows.isNotEmpty)
        throw StateError('Ce médicament existe déjà.');
      final previous = rows.isEmpty
          ? null
          : MedicamentModel.fromSql(rows.first);
      final revision = previous?.revision ?? 0;
      if (medicament.revision != revision) {
        throw StateError(
          'Le stock a changé. Rechargez le médicament avant de modifier.',
        );
      }
      final updated = medicament.copyWith(revision: revision + 1);
      final local = updated.toSql();
      final cloud = updated.toMap();
      if (previous != null) {
        local['created_at'] = previous.createdAt.toIso8601String();
        cloud['created_at'] = previous.toMap()['created_at'];
        await transaction.update(
          'medicaments',
          local,
          where: 'id = ? AND pharmacie_id = ?',
          whereArgs: [updated.id, updated.pharmacieId],
        );
      } else {
        await transaction.insert('medicaments', local);
      }
      await LocalDatabase.addToSyncQueue(
        executor: transaction,
        collection: 'pharmacies/${updated.pharmacieId}/medicaments',
        docId: updated.id,
        operation: 'set',
        data: {'document': cloud, 'expected_revision': revision},
      );
    });
    LocalDatabase.notifyChanged();
    _onChanged?.call();
  }

  Future<List<MedicamentModel>> getMedicaments(String pharmacieId) async {
    _access.read(pharmacieId);
    final db = await _database();
    final rows = await db.query(
      'medicaments',
      where: 'pharmacie_id = ? AND est_actif = 1',
      whereArgs: [pharmacieId],
      orderBy: 'nom ASC',
    );
    _access.read(pharmacieId);
    return rows.map(MedicamentModel.fromSql).toList();
  }

  Future<MedicamentModel?> getMedicamentById(
    String pharmacieId,
    String id,
  ) async {
    _access.read(pharmacieId);
    final db = await _database();
    final rows = await db.query(
      'medicaments',
      where: 'pharmacie_id = ? AND id = ? AND est_actif = 1',
      whereArgs: [pharmacieId, id],
    );
    _access.read(pharmacieId);
    return rows.isEmpty ? null : MedicamentModel.fromSql(rows.first);
  }

  Future<void> deleteMedicament(String pharmacieId, String id) async {
    _access.write(pharmacieId);
    final med = await getMedicamentById(pharmacieId, id);
    if (med == null) throw StateError('Médicament introuvable.');
    await saveMedicament(med.copyWith(estActif: false), isEdit: true);
  }
}
