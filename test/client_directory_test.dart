import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/services/client_directory_service.dart';
import 'fixtures.dart';

void main() {
  test(
    'Annuaire minimal, ancien compte conservé, statut administrateur non écrasé',
    () async {
      final firestore = FakeFirebaseFirestore();
      final data = pharmacie().toMap()..remove('access_status');
      data['fcm_tokens'] = ['secret-device-token'];
      await firestore.doc('pharmacies/pharma-1').set(data);
      final service = ClientDirectoryService(firestore);
      await service.refresh('pharma-1');
      final reference = firestore.doc('clients/pharma-1');
      final initial = (await reference.get()).data()!;
      expect(initial['access_status'], 'active');
      expect(initial.containsKey('fcm_tokens'), isFalse);
      expect(initial.containsKey('tarifs_gros_actifs'), isFalse);
      await reference.update({
        'access_status': 'suspended',
        'access_revision': 1,
      });
      await firestore.doc('pharmacies/pharma-1').update({
        'nom': 'Nouveau nom',
        'access_status': 'suspended',
      });
      await service.refresh('pharma-1');
      final updated = (await reference.get()).data()!;
      expect(updated['nom'], 'Nouveau nom');
      expect(updated['access_status'], 'suspended');
      expect(updated['access_revision'], 1);
      await service.refresh('absent');
      expect((await firestore.doc('clients/absent').get()).exists, isFalse);
    },
  );
}
