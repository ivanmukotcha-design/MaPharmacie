import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/auth_provider.dart';

final pharmacieSettingsServiceProvider = Provider<PharmacieSettingsService>(
  (ref) => PharmacieSettingsService(
    ref.watch(firestoreProvider),
    currentUserId: () => ref.read(currentUserProvider)?.uid,
  ),
);

class PharmacieSettingsService {
  final FirebaseFirestore _firestore;
  final String? Function() _currentUserId;

  PharmacieSettingsService(
    this._firestore, {
    required String? Function() currentUserId,
  }) : _currentUserId = currentUserId;

  Future<void> setWholesaleEnabled(String pharmacieId, bool enabled) async {
    if (_currentUserId() != pharmacieId) throw StateError('Accès refusé.');
    await _firestore.runTransaction((transaction) async {
      final reference = _firestore.doc('pharmacies/$pharmacieId');
      final profile = await transaction.get(reference);
      if (_currentUserId() != pharmacieId || !profile.exists) {
        throw StateError('Profil indisponible ou compte non autorisé.');
      }
      transaction.update(reference, {'tarifs_gros_actifs': enabled});
    });
  }
}
