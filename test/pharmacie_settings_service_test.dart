import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/services/pharmacie_settings_service.dart';
import 'fixtures.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late PharmacieSettingsService service;
  String? userId;
  setUp(() async {
    firestore = FakeFirebaseFirestore();
    userId = 'pharma-1';
    service = PharmacieSettingsService(firestore, currentUserId: () => userId);
    await firestore.doc('pharmacies/pharma-1').set({
      ...pharmacie().toMap(),
      'statut': 'ancien',
    });
  });
  test(
    'Le réglage commun ne remplace pas les autres champs du profil',
    () async {
      await service.setWholesaleEnabled('pharma-1', true);
      final data = (await firestore.doc('pharmacies/pharma-1').get()).data()!;
      expect(data['tarifs_gros_actifs'], isTrue);
      expect(data['nom'], 'Pharmacie');
      expect(data['statut'], 'ancien');
      await service.setWholesaleEnabled('pharma-1', false);
      expect(
        (await firestore.doc('pharmacies/pharma-1').get())
            .data()!['tarifs_gros_actifs'],
        isFalse,
      );
    },
  );
  test('Un autre compte ne peut pas changer le réglage', () async {
    userId = 'autre';
    await expectLater(
      service.setWholesaleEnabled('pharma-1', true),
      throwsStateError,
    );
    await expectLater(
      service.setWholesaleEnabled('autre', true),
      throwsStateError,
    );
  });
  test(
    'Un profil absent ou une session fermée refuse les modifications',
    () async {
      userId = null;
      await expectLater(
        service.setWholesaleEnabled('pharma-1', true),
        throwsStateError,
      );
      userId = 'pharma-1';
      await firestore.doc('pharmacies/pharma-1').delete();
      await expectLater(
        service.setWholesaleEnabled('pharma-1', true),
        throwsStateError,
      );
    },
  );
}
