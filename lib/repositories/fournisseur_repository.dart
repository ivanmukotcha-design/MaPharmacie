import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../local_database/local_database.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import 'repository_access.dart';
import '../config/auth_provider.dart';

final fournisseursProvider = FutureProvider.autoDispose<List<FournisseurModel>>(
  (ref) async {
    ref.watch(localChangesProvider);
    final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return [];
    return ref
        .read(fournisseurRepositoryProvider)
        .getFournisseurs(pharmacie.id);
  },
);

final fournisseurRepositoryProvider = Provider<FournisseurRepository>((ref) {
  final sync = ref.watch(syncServiceProvider);
  return FournisseurRepository(
    RepositoryAccess.forRef(ref),
    onChanged: sync.scheduleSync,
  );
});

class FournisseurRepository {
  final RepositoryAccess _access;
  final Future<Database> Function() _database;
  final void Function()? _onChanged;

  FournisseurRepository(
    this._access, {
    Future<Database> Function()? database,
    void Function()? onChanged,
  }) : _database = database ?? (() => LocalDatabase.database),
       _onChanged = onChanged;

  Future<void> saveFournisseur(FournisseurModel fournisseur) async {
    _access.write(fournisseur.pharmacieId);
    if (fournisseur.nom.trim().isEmpty)
      throw const FormatException('Le nom est requis.');
    final db = await _database();
    await db.transaction((transaction) async {
      _access.write(fournisseur.pharmacieId);
      final rows = await transaction.query(
        'fournisseurs',
        where: 'id = ? AND pharmacie_id = ?',
        whereArgs: [fournisseur.id, fournisseur.pharmacieId],
      );
      final previous = rows.isEmpty
          ? null
          : FournisseurModel.fromSql(rows.first);
      final revision = previous?.revision ?? 0;
      if (revision != fournisseur.revision) {
        throw StateError(
          'Le fournisseur a changé. Rechargez ses informations.',
        );
      }
      final updated = FournisseurModel.fromMap({
        ...fournisseur.toMap(),
        'revision': revision + 1,
        if (previous != null) 'created_at': previous.toMap()['created_at'],
      }, fournisseur.id);
      if (previous == null) {
        await transaction.insert('fournisseurs', updated.toSql());
      } else {
        await transaction.update(
          'fournisseurs',
          updated.toSql(),
          where: 'id = ? AND pharmacie_id = ?',
          whereArgs: [updated.id, updated.pharmacieId],
        );
      }
      await LocalDatabase.addToSyncQueue(
        executor: transaction,
        collection: 'pharmacies/${updated.pharmacieId}/fournisseurs',
        docId: updated.id,
        operation: 'set',
        data: {'document': updated.toMap(), 'expected_revision': revision},
      );
    });
    LocalDatabase.notifyChanged();
    _onChanged?.call();
  }

  Future<List<FournisseurModel>> getFournisseurs(String pharmacieId) async {
    _access.read(pharmacieId);
    final db = await _database();
    final rows = await db.query(
      'fournisseurs',
      where: 'pharmacie_id = ? AND est_actif = 1',
      whereArgs: [pharmacieId],
      orderBy: 'nom ASC',
    );
    _access.read(pharmacieId);
    return rows.map(FournisseurModel.fromSql).toList();
  }

  Future<void> deleteFournisseur(String pharmacieId, String id) async {
    final fournisseurs = await getFournisseurs(pharmacieId);
    final fournisseur = fournisseurs.firstWhere((entry) => entry.id == id);
    await saveFournisseur(
      FournisseurModel.fromMap({
        ...fournisseur.toMap(),
        'est_actif': false,
      }, id),
    );
  }
}
