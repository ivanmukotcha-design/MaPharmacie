import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../local_database/local_database.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import 'medicament_repository.dart';

final venteRepositoryProvider = Provider<VenteRepository>((ref) {
  return VenteRepository(
    ref.watch(medicamentRepositoryProvider),
    ref.watch(isOnlineProvider),
  );
});

class VenteRepository {
  final MedicamentRepository _medicamentRepo;
  final bool _isOnline;

  VenteRepository(this._medicamentRepo, this._isOnline);

  /// Effectue une vente complète : 
  /// 1. Enregistre la vente
  /// 2. Met à jour le stock pour chaque item
  Future<void> effectuerVente(VenteModel vente) async {
    // 1. Sauvegarde locale de la vente
    final venteMap = vente.toMap();
    final itemsMap = vente.items.map((i) {
      final m = i.toMap();
      m['id'] = const Uuid().v4();
      m['vente_id'] = vente.id;
      return m;
    }).toList();

    await LocalDatabase.insertVente(venteMap, itemsMap);

    // 2. Mise à jour du stock local et Cloud pour chaque médicament
    for (final item in vente.items) {
      final medicament = await _medicamentRepo.getMedicamentById(vente.pharmacieId, item.medicamentId);
      if (medicament != null) {
        // Déduire la quantité
        final nouveauStock = medicament.unites.deduire(item.quantite, item.unite);
        final medMisAJour = MedicamentModel(
          id: medicament.id,
          pharmacieId: medicament.pharmacieId,
          nom: medicament.nom,
          categorie: medicament.categorie,
          description: medicament.description,
          prixGrossiste: medicament.prixGrossiste,
          prixDetail: medicament.prixDetail,
          fournisseurId: medicament.fournisseurId,
          fournisseurNom: medicament.fournisseurNom,
          seuilAlerte: medicament.seuilAlerte,
          unites: nouveauStock,
          estActif: medicament.estActif,
          createdAt: medicament.createdAt,
          updatedAt: DateTime.now(),
          dateExpiration: medicament.dateExpiration,
          codeBarres: medicament.codeBarres,
        );
        
        await _medicamentRepo.saveMedicament(medMisAJour, isEdit: true);
      }
    }

    // 3. Sync Cloud de la vente
    if (_isOnline) {
      await FirebaseFirestore.instance
          .collection(AppConstants.colPharmacies)
          .doc(vente.pharmacieId)
          .collection(AppConstants.colVentes)
          .doc(vente.id)
          .set(venteMap);
    } else {
      await LocalDatabase.addToSyncQueue(
        collection: '${AppConstants.colPharmacies}/${vente.pharmacieId}/${AppConstants.colVentes}',
        docId: vente.id,
        operation: 'set',
        data: venteMap,
      );
    }
  }

  Future<List<VenteModel>> getHistoriqueVentes(String pharmacieId) async {
    final list = await LocalDatabase.getVentes(pharmacieId);
    final ventes = <VenteModel>[];
    
    for (final v in list) {
      final items = await LocalDatabase.getVenteItems(v['id']);
      final map = Map<String, dynamic>.from(v);
      map['items'] = items;
      ventes.add(VenteModel.fromMap(map, v['id']));
    }
    return ventes;
  }
}
