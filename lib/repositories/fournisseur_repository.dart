import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../local_database/local_database.dart';
import '../models/models.dart';
import '../services/sync_service.dart';

final fournisseurRepositoryProvider = Provider<FournisseurRepository>((ref) {
  return FournisseurRepository(
    ref.watch(syncServiceProvider),
    ref.watch(isOnlineProvider),
  );
});

class FournisseurRepository {
  final SyncService _syncService;
  final bool _isOnline;

  FournisseurRepository(this._syncService, this._isOnline);

  Future<void> saveFournisseur(FournisseurModel fournisseur) async {
    final data = fournisseur.toMap();
    
    // 1. Local
    final localData = Map<String, dynamic>.from(data);
    localData['id'] = fournisseur.id;
    localData['created_at'] = fournisseur.createdAt.toIso8601String();
    localData['synced'] = _isOnline ? 1 : 0;

    final db = await LocalDatabase.database;
    await db.insert('fournisseurs', localData, conflictAlgorithm: ConflictAlgorithm.replace);

    // 2. Cloud
    if (_isOnline) {
      await FirebaseFirestore.instance
          .collection(AppConstants.colPharmacies)
          .doc(fournisseur.pharmacieId)
          .collection(AppConstants.colFournisseurs)
          .doc(fournisseur.id)
          .set(data, SetOptions(merge: true));
    } else {
      await LocalDatabase.addToSyncQueue(
        collection: '${AppConstants.colPharmacies}/${fournisseur.pharmacieId}/${AppConstants.colFournisseurs}',
        docId: fournisseur.id,
        operation: 'set',
        data: data,
      );
    }
  }

  Future<List<FournisseurModel>> getFournisseurs(String pharmacieId) async {
    final db = await LocalDatabase.database;
    final list = await db.query(
      'fournisseurs',
      where: 'pharmacie_id = ?',
      whereArgs: [pharmacieId],
      orderBy: 'nom ASC',
    );

    return list.map((f) {
      final map = Map<String, dynamic>.from(f);
      map['created_at'] = Timestamp.fromDate(DateTime.parse(f['created_at'] as String));
      return FournisseurModel.fromMap(map, f['id'] as String);
    }).toList();
  }

  Future<void> deleteFournisseur(String pharmacieId, String id) async {
    final db = await LocalDatabase.database;
    await db.delete('fournisseurs', where: 'id = ?', whereArgs: [id]);

    if (_isOnline) {
      await FirebaseFirestore.instance
          .collection(AppConstants.colPharmacies)
          .doc(pharmacieId)
          .collection(AppConstants.colFournisseurs)
          .doc(id)
          .delete();
    } else {
      await LocalDatabase.addToSyncQueue(
        collection: '${AppConstants.colPharmacies}/$pharmacieId/${AppConstants.colFournisseurs}',
        docId: id,
        operation: 'delete',
      );
    }
  }
}
