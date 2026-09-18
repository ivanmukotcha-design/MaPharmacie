import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../core/utils/validators.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);
final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(authStateProvider).valueOrNull,
);

final currentPharmacieProvider = StreamProvider<PharmacieModel?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('pharmacies')
      .doc(user.uid)
      .snapshots()
      .map(
        (snapshot) => snapshot.exists
            ? PharmacieModel.fromMap(snapshot.data()!, snapshot.id)
            : null,
      );
});

final pharmacieAuthorizedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  final profile = ref.watch(currentPharmacieProvider);
  return user != null &&
      !profile.hasError &&
      profile.valueOrNull?.id == user.uid;
});

final wholesaleEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(pharmacieAuthorizedProvider) &&
      ref.watch(currentPharmacieProvider).valueOrNull?.tarifsGrosActifs == true,
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
  ),
);

class AuthService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  AuthService(this._firestore, this._auth);

  Future<UserCredential> loginWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (result.user != null) {
      await NotificationService.updateTokenForPharmacie(result.user!.uid);
    }
    return result;
  }

  Future<void> createAccount(String email, String password) async {
    if (_auth.currentUser != null)
      throw StateError('Une session est déjà ouverte.');
    if (validateEmail(email) != null || validatePassword(password) != null) {
      throw const FormatException('Email ou mot de passe invalide.');
    }
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> logout() async {
    await NotificationService.detachCurrentUser();
    await _auth.signOut();
  }

  Future<PharmacieModel> creerPharmacie({
    required String nom,
    required String telephone,
    required String adresse,
    required String ville,
    required String pays,
    required String proprietaireNom,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null)
      throw StateError('Connexion requise.');
    final values = [nom, telephone, adresse, ville, pays, proprietaireNom];
    if (values.any((value) => value.trim().isEmpty)) {
      throw const FormatException(
        'Complétez les informations de la pharmacie.',
      );
    }
    if (_auth.currentUser?.uid != user.uid)
      throw StateError('La session a changé.');
    final profile = PharmacieModel(
      id: user.uid,
      code: 'PHR-${user.uid}',
      nom: nom.trim(),
      username: '',
      email: user.email!,
      telephone: telephone.trim(),
      adresse: adresse.trim(),
      ville: ville.trim(),
      pays: pays.trim(),
      proprietaireNom: proprietaireNom.trim(),
      createdAt: DateTime.now(),
    );
    final reference = _firestore.collection('pharmacies').doc(user.uid);
    await _firestore.runTransaction((transaction) async {
      final previous = await transaction.get(reference);
      if (previous.exists)
        throw StateError(
          'La pharmacie est déjà configurée. Rechargez votre profil.',
        );
      if (_auth.currentUser?.uid != user.uid)
        throw StateError('La session a changé.');
      transaction.set(reference, {
        ...profile.toMap(),
        'created_at': FieldValue.serverTimestamp(),
      });
    });
    await NotificationService.updateTokenForPharmacie(user.uid);
    return profile;
  }
}
