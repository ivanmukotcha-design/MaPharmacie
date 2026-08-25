import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../local_database/local_database.dart';
import '../models/models.dart';
import '../services/sync_service.dart';

final medicamentRepositoryProvider = Provider<MedicamentRepository>((ref) {
  return MedicamentRepository(
    ref.watch(syncServiceProvider),
    ref.watch(isOnlineProvider),
  );
});

class MedicamentRepository {
  final SyncService _syncService;
  final bool _isOnline;

  MedicamentRepository(this._syncService, this._isOnline);

  Future<void> saveMedicament(MedicamentModel medicament, {bool isEdit = false}) async {
    final data = medicament.toMap();
    
    // 1. Sauvegarde locale (Source de vérité immédiate)
    // On adapte le map pour Sqflite (conversion des types non supportés comme DateTime)
    final localData = Map<String, dynamic>.from(data);
    localData['id'] = medicament.id;
    localData['date_expiration'] = medicament.dateExpiration?.toIso8601String();
    localData['created_at'] = medicament.createdAt.toIso8601String();
    localData['updated_at'] = medicament.updatedAt.toIso8601String();
    
    // Aplatir les unités pour le SQL
    localData['cartons'] = medicament.unites.cartons;
    localData['boites'] = medicament.unites.boites;
    localData['plaquettes'] = medicament.unites.plaquettes;
    localData['comprimes'] = medicament.unites.comprimes;
    localData['flacons'] = medicament.unites.flacons;
    localData['cartons_par_boite'] = medicament.unites.cartonsParBoite;
    localData['boites_par_plaquette'] = medicament.unites.boitesParPlaquette;
    localData['plaquettes_par_comprime'] = medicament.unites.plaquettesParComprime;
    localData.remove('unites');
    
    localData['synced'] = _isOnline ? 1 : 0;
    localData['est_actif'] = medicament.estActif ? 1 : 0;

    await LocalDatabase.upsertMedicament(localData);

    // 2. Sauvegarde Cloud ou Queue de sync
    if (_isOnline) {
      await FirebaseFirestore.instance
          .collection(AppConstants.colPharmacies)
          .doc(medicament.pharmacieId)
          .collection(AppConstants.colMedicaments)
          .doc(medicament.id)
          .set(data, SetOptions(merge: true));
    } else {
      await LocalDatabase.addToSyncQueue(
        collection: '${AppConstants.colPharmacies}/${medicament.pharmacieId}/${AppConstants.colMedicaments}',
        docId: medicament.id,
        operation: 'set',
        data: data,
      );
    }
  }

  Future<List<MedicamentModel>> getMedicaments(String pharmacieId) async {
    final list = await LocalDatabase.getMedicaments(pharmacieId);
    return list.map((m) {
      // Re-transformer le format SQL en format Modèle
      final map = Map<String, dynamic>.from(m);
      map['created_at'] = Timestamp.fromDate(DateTime.parse(m['created_at']));
      map['updated_at'] = Timestamp.fromDate(DateTime.parse(m['updated_at']));
      if (m['date_expiration'] != null) {
        map['date_expiration'] = Timestamp.fromDate(DateTime.parse(m['date_expiration']));
      }
      map['unites'] = {
        'cartons': m['cartons'],
        'boites': m['boites'],
        'plaquettes': m['plaquettes'],
        'comprimes': m['comprimes'],
        'flacons': m['flacons'],
        'cartons_par_boite': m['cartons_par_boite'],
        'boites_par_plaquette': m['boites_par_plaquette'],
        'plaquettes_par_comprime': m['plaquettes_par_comprime'],
      };
      return MedicamentModel.fromMap(map, m['id']);
    }).toList();
  }

  Future<MedicamentModel?> getMedicamentById(String pharmacieId, String id) async {
    final meds = await getMedicaments(pharmacieId);
    try {
      return meds.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteMedicament(String pharmacieId, String id) async {
    await LocalDatabase.deleteMedicament(id);
    
    if (_isOnline) {
      await FirebaseFirestore.instance
          .collection(AppConstants.colPharmacies)
          .doc(pharmacieId)
          .collection(AppConstants.colMedicaments)
          .doc(id)
          .update({'est_actif': false, 'updated_at': FieldValue.serverTimestamp()});
    } else {
      await LocalDatabase.addToSyncQueue(
        collection: '${AppConstants.colPharmacies}/$pharmacieId/${AppConstants.colMedicaments}',
        docId: id,
        operation: 'update',
        data: {'est_actif': false},
      );
    }
  }
}
