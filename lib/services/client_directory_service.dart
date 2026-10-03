import 'package:cloud_firestore/cloud_firestore.dart';

class ClientDirectoryService {
  final FirebaseFirestore firestore;
  ClientDirectoryService(this.firestore);

  static Map<String, dynamic> contact(Map<String, dynamic> profile) => {
    for (final field in [
      'nom',
      'email',
      'telephone',
      'adresse',
      'ville',
      'pays',
      'proprietaire_nom',
    ])
      field: profile[field] ?? '',
    'created_at': profile['created_at'],
  };

  static Map<String, dynamic> initial(Map<String, dynamic> profile) => {
    ...contact(profile),
    'access_status': profile['access_status'] ?? 'active',
    'access_revision': profile['access_revision'] ?? 0,
    'last_access_event': profile['last_access_event'] ?? '',
    'activated_at': profile['activated_at'],
  };

  Future<void> refresh(String owner) => firestore.runTransaction((
    transaction,
  ) async {
    final profile = await transaction.get(firestore.doc('pharmacies/$owner'));
    final reference = firestore.doc('clients/$owner');
    final existing = await transaction.get(reference);
    if (!profile.exists) return;
    final data = profile.data()!;
    if (!existing.exists) {
      transaction.set(reference, initial(data));
    } else {
      final fields = contact(data);
      if (fields.entries.any(
        (entry) => existing.data()![entry.key] != entry.value,
      )) {
        transaction.update(reference, fields);
      }
    }
  });
}
