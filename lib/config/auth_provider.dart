import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../core/utils/validators.dart';
import '../services/client_directory_service.dart';

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
  if (user == null || !user.emailVerified) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('pharmacies')
      .doc(user.uid)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        if (!snapshot.exists) return null;
        if (!snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites) {
          unawaited(
            ClientDirectoryService(
              ref.read(firestoreProvider),
            ).refresh(user.uid).catchError((Object error) {
              debugPrint(
                'Annuaire client non actualisé : ${error.runtimeType}',
              );
            }),
          );
        }
        return PharmacieModel.fromMap(snapshot.data()!, snapshot.id);
      });
});

final pharmacieAuthorizedProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  final profile = ref.watch(currentPharmacieProvider);
  return user != null &&
      user.emailVerified &&
      !profile.hasError &&
      profile.valueOrNull?.id == user.uid &&
      profile.valueOrNull?.canReadData == true;
});

final pharmacieWritableProvider = Provider<bool>(
  (ref) =>
      ref.watch(pharmacieAuthorizedProvider) &&
      ref.watch(currentPharmacieProvider).valueOrNull?.canWriteData == true,
);

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
  String? _verificationUid;
  DateTime? _verificationSentAt;
  bool _sendingVerification = false;
  AuthService(this._firestore, this._auth);

  Future<UserCredential> loginWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (result.user?.emailVerified == true) {
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

  int get verificationResendSeconds {
    if (_verificationUid != _auth.currentUser?.uid ||
        _verificationSentAt == null) {
      return 0;
    }
    final remaining =
        60 - DateTime.now().difference(_verificationSentAt!).inSeconds;
    return remaining.clamp(0, 60);
  }

  Future<bool> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    if (user.emailVerified ||
        _sendingVerification ||
        verificationResendSeconds > 0) {
      return false;
    }
    _sendingVerification = true;
    try {
      await _auth.setLanguageCode('fr');
      if (_auth.currentUser?.uid != user.uid) {
        throw StateError('La session a changé.');
      }
      await user.sendEmailVerification();
      _verificationUid = user.uid;
      _verificationSentAt = DateTime.now();
      return true;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'too-many-requests') {
        _verificationUid = user.uid;
        _verificationSentAt = DateTime.now();
      }
      rethrow;
    } finally {
      _sendingVerification = false;
    }
  }

  Future<bool> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null || refreshed.uid != user.uid) {
      throw StateError('La session a changé.');
    }
    if (!refreshed.emailVerified) return false;
    final token = await refreshed.getIdTokenResult(true);
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('La session a changé.');
    }
    return token.claims?['email_verified'] == true;
  }

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
    if (!user.emailVerified) {
      throw StateError('Confirmez votre adresse email avant de continuer.');
    }
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
      accessStatus: 'pending',
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
      final data = {
        ...profile.toMap(),
        'created_at': FieldValue.serverTimestamp(),
      };
      transaction.set(reference, data);
      transaction.set(
        _firestore.doc('clients/${user.uid}'),
        ClientDirectoryService.initial(data),
      );
    });
    await NotificationService.updateTokenForPharmacie(user.uid);
    return profile;
  }
}
