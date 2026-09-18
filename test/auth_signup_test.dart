import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/features/auth/presentation/create_account_screen.dart';
import 'package:pharmaflow/features/auth/presentation/login_screen.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  @override
  final String email;
  _User(this.uid, this.email);
}

class _Credential extends Fake implements UserCredential {
  @override
  final User user;
  _Credential(this.user);
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;
  FirebaseAuthException? failure;
  Future<void>? pending;
  int calls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  User? get currentUser => user;

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    calls++;
    lastEmail = email;
    lastPassword = password;
    if (pending != null) await pending;
    if (failure != null) throw failure!;
    user = _User('nouvelle-pharmacie', email);
    return _Credential(user!);
  }
}

void main() {
  late _Auth auth;
  late FakeFirebaseFirestore firestore;
  late AuthService service;

  setUp(() {
    auth = _Auth();
    firestore = FakeFirebaseFirestore();
    service = AuthService(firestore, auth);
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> configureProfile({String name = 'Pharmacie test'}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await service.creerPharmacie(
      nom: name,
      telephone: '123',
      adresse: 'Rue',
      ville: 'Ville',
      pays: 'Pays',
      proprietaireNom: 'Responsable',
    );
  }

  test(
    'Création autonome puis profil au même UID sans configuration préalable',
    () async {
      await service.createAccount(' pharmacie@example.com ', ' password123 ');
      expect(auth.lastEmail, 'pharmacie@example.com');
      expect(auth.lastPassword, ' password123 ');
      expect(
        (await firestore.doc('config/installation').get()).exists,
        isFalse,
      );
      expect(
        (await firestore.doc('pharmacies/nouvelle-pharmacie').get()).exists,
        isFalse,
      );
      await configureProfile();
      final profile =
          (await firestore.doc('pharmacies/nouvelle-pharmacie').get()).data()!;
      expect(profile['email'], 'pharmacie@example.com');
      expect(profile['code'], 'PHR-nouvelle-pharmacie');
      expect(profile['tarifs_gros_actifs'], isFalse);
      expect(profile['created_at'], isA<Timestamp>());
    },
  );

  test(
    'Un profil incomplet se reprend sans recréer ni supprimer le compte Auth',
    () async {
      await service.createAccount('pharmacie@example.com', 'password123');
      await expectLater(configureProfile(name: ' '), throwsFormatException);
      expect(auth.currentUser?.uid, 'nouvelle-pharmacie');
      await configureProfile();
      expect(auth.calls, 1);
      await expectLater(configureProfile(name: 'Autre nom'), throwsStateError);
      expect(
        (await firestore.doc('pharmacies/nouvelle-pharmacie').get())
            .data()!['nom'],
        'Pharmacie test',
      );
    },
  );

  test(
    'Validation avant Firebase et aucune création depuis une session ouverte',
    () async {
      await expectLater(
        service.createAccount('incorrect', 'password123'),
        throwsFormatException,
      );
      await expectLater(
        service.createAccount('test@example.com', '123'),
        throwsFormatException,
      );
      expect(auth.calls, 0);
      auth.user = _User('existant', 'test@example.com');
      await expectLater(
        service.createAccount('autre@example.com', 'password123'),
        throwsStateError,
      );
      expect(auth.calls, 0);
      expect(auth.currentUser?.uid, 'existant');
    },
  );

  test('Un email déjà inscrit ne crée ni nouveau compte ni profil', () async {
    auth.failure = FirebaseAuthException(code: 'email-already-in-use');
    await expectLater(
      service.createAccount('test@example.com', 'password123'),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(auth.currentUser, isNull);
    expect((await firestore.collection('pharmacies').get()).docs, isEmpty);
  });

  Future<void> showSignup(
    WidgetTester tester, {
    String initial = '/register',
  }) async {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
          path: '/register',
          builder: (_, __) => const CreateAccountScreen(),
        ),
        GoRoute(
          path: '/configurer',
          builder: (_, __) => const Scaffold(body: Text('Profil à compléter')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(service)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillSignup(
    WidgetTester tester, {
    String confirmation = 'password123',
  }) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'pharmacie@example.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.enterText(fields.at(2), confirmation);
    await tester.ensureVisible(find.text('Créer mon compte'));
  }

  testWidgets('Le bouton du login ouvre l’inscription autonome', (
    tester,
  ) async {
    await showSignup(tester, initial: '/login');
    await tester.ensureVisible(find.text('Créer un compte'));
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    expect(find.byType(CreateAccountScreen), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
  });

  testWidgets('Les champs invalides et la confirmation bloquent la création', (
    tester,
  ) async {
    await showSignup(tester);
    await tester.ensureVisible(find.text('Créer mon compte'));
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    expect(find.text('Email valide requis'), findsOneWidget);
    expect(auth.calls, 0);
    await fillSignup(tester, confirmation: 'different');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    expect(
      find.text('Les mots de passe ne correspondent pas.'),
      findsOneWidget,
    );
    expect(auth.calls, 0);
  });

  testWidgets(
    'Une seule création est envoyée puis le formulaire pharmacie apparaît',
    (tester) async {
      final pending = Completer<void>();
      auth.pending = pending.future;
      await showSignup(tester);
      await fillSignup(tester);
      await tester.tap(find.text('Créer mon compte'));
      await tester.pump();
      await tester.tap(find.byType(ElevatedButton));
      expect(auth.calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Profil à compléter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Email existant : proposer la connexion, pas une nouvelle pharmacie',
    (tester) async {
      auth.failure = FirebaseAuthException(code: 'email-already-in-use');
      await showSignup(tester);
      await fillSignup(tester);
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cet email est déjà utilisé.'),
        findsOneWidget,
      );
      expect(find.text('Profil à compléter'), findsNothing);
      expect(auth.currentUser, isNull);
    },
  );
}
