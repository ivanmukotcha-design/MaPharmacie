import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/access_policy.dart';
import 'package:pharmaflow/models/models.dart';
import 'fixtures.dart';

void main() {
  String? redirect({
    String location = '/stock',
    String? userId = 'pharma-1',
    bool profile = true,
    bool loading = false,
    bool hasError = false,
  }) => sessionRedirect(
    location: location,
    loading: loading,
    hasError: hasError,
    userId: userId,
    pharmacie: profile ? pharmacie() : null,
  );

  test('Connexion et inscription publiques, données protégées', () {
    expect(redirect(userId: null, location: '/login'), isNull);
    expect(redirect(userId: null, location: '/register'), isNull);
    expect(redirect(userId: null, location: '/stock'), '/login');
    expect(redirect(userId: null, location: '/configurer'), '/login');
    expect(redirect(userId: null, location: '/activation'), '/login');
  });
  test('Tout nouveau compte peut compléter son profil sans technicien', () {
    expect(redirect(profile: false, userId: 'nouveau'), '/configurer');
    expect(redirect(profile: false, location: '/configurer'), isNull);
    expect(redirect(profile: false, location: '/register'), '/configurer');
    expect(redirect(profile: false, location: '/login'), '/configurer');
  });
  test('Un profil d’un autre compte ne donne aucun accès', () {
    expect(redirect(userId: 'autre'), '/acces');
    expect(redirect(), isNull);
    expect(redirect(location: '/ventes'), isNull);
  });
  test('Un compte existant retrouve sa pharmacie au lieu de la recréer', () {
    for (final location in [
      '/register',
      '/login',
      '/configurer',
      '/admin',
      '/abonnement',
    ]) {
      expect(redirect(location: location), '/dashboard');
    }
  });
  test(
    'Une erreur de profil ne doit pas être traitée comme un profil absent',
    () {
      expect(redirect(profile: false, hasError: true), '/acces');
      expect(redirect(profile: false, loading: true), '/splash');
      expect(redirect(hasError: true, location: '/acces'), isNull);
      expect(redirect(loading: true, location: '/splash'), isNull);
    },
  );
  test('Les anciens champs abonnement ne bloquent plus le compte', () {
    final legacy = PharmacieModel.fromMap({
      ...pharmacie().toMap(),
      'statut': 'suspendu',
      'abonnement_fin': DateTime(2020),
      'type_pharmacie': 'grossiste',
    }, 'pharma-1');
    expect(legacy.tarifsGrosActifs, isFalse);
    expect(
      sessionRedirect(
        location: '/ventes',
        loading: false,
        hasError: false,
        userId: 'pharma-1',
        pharmacie: legacy,
      ),
      isNull,
    );
  });
}
