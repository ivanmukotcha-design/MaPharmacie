import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../core/constants/app_constants.dart';

class AbonnementService {
  final FirebaseFirestore _firestore;

  AbonnementService(this._firestore);

  Stream<AbonnementModel?> watchAbonnement(String pharmacieId) {
    return _firestore
        .collection(AppConstants.colAbonnements)
        .where('pharmacie_id', isEqualTo: pharmacieId)
        .where('est_actif', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          return AbonnementModel.fromMap(snap.docs.first.data(), snap.docs.first.id);
        });
  }

  Future<AbonnementModel?> getAbonnementActif(String pharmacieId) async {
    final snap = await _firestore
        .collection(AppConstants.colAbonnements)
        .where('pharmacie_id', isEqualTo: pharmacieId)
        .where('est_actif', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AbonnementModel.fromMap(snap.docs.first.data(), snap.docs.first.id);
  }

  Future<void> traiterRenouvellement({
    required String pharmacieId,
    required double montant,
    required String methode,
    required String reference,
  }) async {
    final batch = _firestore.batch();
    final now = DateTime.now();
    final dateFin = DateTime(now.year, now.month + 1, now.day);

    // 1. Désactiver l'ancien abonnement
    final oldSnap = await _firestore
        .collection(AppConstants.colAbonnements)
        .where('pharmacie_id', isEqualTo: pharmacieId)
        .where('est_actif', isEqualTo: true)
        .get();

    for (final doc in oldSnap.docs) {
      batch.update(doc.reference, {'est_actif': false});
    }

    // 2. Créer le nouvel abonnement (en attente de validation admin)
    final newAbonRef = _firestore.collection(AppConstants.colAbonnements).doc();
    batch.set(newAbonRef, {
      'pharmacie_id': pharmacieId,
      'date_debut': Timestamp.fromDate(now),
      'date_fin': Timestamp.fromDate(dateFin),
      'montant_total': montant,
      'montant_paye': 0,
      'statut': 'en_attente',
      'est_actif': true,
      'created_at': FieldValue.serverTimestamp(),
    });

    // 3. Enregistrer le paiement lié
    final newPaiementRef = _firestore.collection(AppConstants.colPaiements).doc();
    batch.set(newPaiementRef, {
      'pharmacie_id': pharmacieId,
      'abonnement_id': newAbonRef.id,
      'montant': montant,
      'type_paiement': methode,
      'statut_paiement': 'en_attente',
      'type_paiement_abonnement': 'renouvellement',
      'reference': reference,
      'date': FieldValue.serverTimestamp(),
      'valide_par': false,
    });

    await batch.commit();
  }

  Future<List<PaiementModel>> getHistoriquePaiements(String pharmacieId) async {
    final snap = await _firestore
        .collection(AppConstants.colPaiements)
        .where('pharmacie_id', isEqualTo: pharmacieId)
        .orderBy('date', descending: true)
        .get();
    return snap.docs.map((d) => PaiementModel.fromMap(d.data(), d.id)).toList();
  }
}

// ─── PROVIDERS ────────────────────────────────────────────────────────────────

final abonnementServiceProvider = Provider<AbonnementService>((ref) {
  return AbonnementService(FirebaseFirestore.instance);
});

final abonnementActifProvider = StreamProvider.family<AbonnementModel?, String>(
  (ref, pharmacieId) => ref.watch(abonnementServiceProvider).watchAbonnement(pharmacieId),
);

final historiquePaiementsProvider = FutureProvider.family<List<PaiementModel>, String>(
  (ref, pharmacieId) => ref.watch(abonnementServiceProvider).getHistoriquePaiements(pharmacieId),
);

final tarifsProvider = FutureProvider<TarifsConfig>((ref) async {
  final snap = await FirebaseFirestore.instance
      .collection(AppConstants.colConfig)
      .doc(AppConstants.docTarifs)
      .get();
  
  if (snap.exists) return TarifsConfig.fromMap(snap.data()!);
  
  return TarifsConfig(
    fraisCreationCompte: 5000,
    abonnementMensuelDetaillant: 10000,
    abonnementMensuelGrossiste: 25000,
    updatedAt: DateTime.now(),
  );
});
