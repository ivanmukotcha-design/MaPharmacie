import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/models.dart';
import '../core/constants/app_constants.dart';
import '../services/notification_service.dart';

// Providers de base Firebase pour l'injection de dépendances
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Provider qui écoute les changements d'état de l'authentification
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Provider pour récupérer l'utilisateur actuel
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Source de vérité pour la pharmacie connectée
final currentPharmacieProvider = StreamProvider<PharmacieModel?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  return ref.watch(firestoreProvider)
      .collection(AppConstants.colPharmacies)
      .doc(user.uid)
      .snapshots()
      .map((snap) {
        if (!snap.exists) return null;
        return PharmacieModel.fromMap(snap.data()!, snap.id);
      });
});

/// Service d'authentification
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firestoreProvider), ref.watch(firebaseAuthProvider));
});

class AuthService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthService(this._firestore, this._auth);

  Future<UserCredential> loginWithEmail(String email, String password) async {
    final creds = await _auth.signInWithEmailAndPassword(email: email, password: password);
    if (creds.user != null) {
      // Met à jour le token FCM au login
      await NotificationService.updateTokenForPharmacie(creds.user!.uid);
    }
    return creds;
  }

  Future<UserCredential> loginWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) throw Exception('Connexion Google annulée');
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    final creds = await _auth.signInWithCredential(credential);
    if (creds.user != null) {
      await NotificationService.updateTokenForPharmacie(creds.user!.uid);
    }
    return creds;
  }

  Future<UserCredential> registerWithEmail(String email, String password) async {
    final creds = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    if (creds.user != null) {
      // Important : Enregistre le token aussi à l'inscription
      await NotificationService.updateTokenForPharmacie(creds.user!.uid);
    }
    return creds;
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<bool> isAdmin(String userId) async {
    final doc = await _firestore.collection('admins').doc(userId).get();
    return doc.exists;
  }

  Future<PharmacieModel> creerPharmacie({
    required String userId,
    required String nom,
    required String email,
    required String telephone,
    required String adresse,
    required String ville,
    required String pays,
    required String typePharmacie,
    required String proprietaireNom,
  }) async {
    final code = await _generateCode();

    final pharmaData = {
      'code': code,
      'nom': nom,
      'email': email,
      'telephone': telephone,
      'adresse': adresse,
      'ville': ville,
      'pays': pays,
      'type_pharmacie': typePharmacie,
      'statut': PharmacieStatut.actif,
      'proprietaire_nom': proprietaireNom,
      'created_at': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection(AppConstants.colPharmacies)
        .doc(userId)
        .set(pharmaData);

    return PharmacieModel(
      id: userId,
      code: code,
      nom: nom,
      email: email,
      telephone: telephone,
      adresse: adresse,
      ville: ville,
      pays: pays,
      typePharmacie: typePharmacie,
      statut: PharmacieStatut.actif,
      proprietaireNom: proprietaireNom,
      createdAt: DateTime.now(),
    );
  }

  Future<String> _generateCode() async {
    final count = await _firestore.collection(AppConstants.colPharmacies).count().get();
    final num = (count.count ?? 0) + 1;
    return 'PHR-${num.toString().padLeft(4, '0')}';
  }
}
