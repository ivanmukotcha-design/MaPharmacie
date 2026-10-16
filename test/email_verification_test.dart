import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/access_policy.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/config/router.dart';
import 'package:pharmaflow/features/auth/presentation/verify_email_screen.dart';
import 'package:pharmaflow/features/auth/presentation/register_screen.dart';
import 'package:pharmaflow/features/auth/presentation/access_screen.dart';
import 'package:pharmaflow/repositories/repository_access.dart';

import 'fixtures.dart';

class _Token extends Fake implements IdTokenResult {
  @override
  final Map<String, dynamic> claims;
  _Token(bool verified) : claims = {'email_verified': verified};
}

class _User extends Fake implements User {
  @override
  String get uid => 'pharma-1';
  @override
  String get email => 'pharmacie@example.com';
  @override
  bool emailVerified = false;
  bool confirmedRemotely = false;
  bool tokenVerified = true;
  bool forcedToken = false;
  int sends = 0;
  FirebaseAuthException? sendError;
  FirebaseAuthException? reloadError;
  Completer<void>? pendingSend;
  VoidCallback? afterReload;

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    sends++;
    await pendingSend?.future;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> reload() async {
    if (reloadError != null) throw reloadError!;
    emailVerified = confirmedRemotely;
    afterReload?.call();
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    forcedToken = forceRefresh;
    return _Token(tokenVerified);
  }
}

class _Credential extends Fake implements UserCredential {
  @override
  final User user;
  _Credential(this.user);
}

class _Auth extends Fake implements FirebaseAuth {
  _User? user = _User();
  String? language;
  String? passwordReceived;
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => Stream.value(user);
  @override
  Future<void> setLanguageCode(String? languageCode) async =>
      language = languageCode;
  @override
  Future<void> signOut() async => user = null;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    passwordReceived = password;
    if (email != 'pharmacie@example.com' ||
        password != 'application-password') {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
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

  test(
    'Le mot de passe de l’application reste contrôlé par Firebase',
    () async {
      await expectLater(
        service.loginWithEmail('pharmacie@example.com', 'incorrect'),
        throwsA(isA<FirebaseAuthException>()),
      );
      await expectLater(
        service.loginWithEmail('inconnu@example.com', 'application-password'),
        throwsA(isA<FirebaseAuthException>()),
      );
      final result = await service.loginWithEmail(
        'pharmacie@example.com',
        'application-password',
      );
      expect(result.user!.emailVerified, isFalse);
      expect(auth.passwordReceived, 'application-password');
    },
  );

  test(
    'Envoi en français, sans doublon simultané et avec délai de renvoi',
    () async {
      final pending = Completer<void>();
      auth.user!.pendingSend = pending;
      final sending = service.sendVerificationEmail();
      await Future<void>.delayed(Duration.zero);
      expect(await service.sendVerificationEmail(), isFalse);
      pending.complete();
      expect(await sending, isTrue);
      expect(await service.sendVerificationEmail(), isFalse);
      expect(auth.language, 'fr');
      expect(auth.user!.sends, 1);
      expect(service.verificationResendSeconds, greaterThan(0));
      expect(auth.user!.emailVerified, isFalse);
    },
  );

  test('Échec réseau réessayable sans recréer le compte', () async {
    auth.user!.sendError = FirebaseAuthException(
      code: 'network-request-failed',
    );
    await expectLater(
      service.sendVerificationEmail(),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(service.verificationResendSeconds, 0);
    auth.user!.sendError = null;
    expect(await service.sendVerificationEmail(), isTrue);
    expect(auth.user!.uid, 'pharma-1');
  });

  test(
    'La confirmation recharge le compte et exige un jeton serveur actualisé',
    () async {
      expect(await service.refreshEmailVerification(), isFalse);
      expect(auth.user!.forcedToken, isFalse);
      auth.user!.confirmedRemotely = true;
      auth.user!.tokenVerified = false;
      expect(await service.refreshEmailVerification(), isFalse);
      expect(auth.user!.forcedToken, isTrue);
      auth.user!.tokenVerified = true;
      expect(await service.refreshEmailVerification(), isTrue);
    },
  );

  test(
    'Un changement de session ou une erreur serveur ne valide rien',
    () async {
      auth.user!.reloadError = FirebaseAuthException(
        code: 'network-request-failed',
      );
      await expectLater(
        service.refreshEmailVerification(),
        throwsA(isA<FirebaseAuthException>()),
      );
      auth.user!.reloadError = null;
      auth.user!.afterReload = () => auth.user = null;
      await expectLater(service.refreshEmailVerification(), throwsStateError);
    },
  );

  test(
    'Un compte actif non confirmé ne lit ni profil ni données métier',
    () async {
      await firestore.doc('pharmacies/pharma-1').set(pharmacie().toMap());
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authStateProvider.future);
      expect(await container.read(currentPharmacieProvider.future), isNull);
      expect(container.read(pharmacieAuthorizedProvider), isFalse);
      expect(
        () => container.read(repositoryAccessProvider).read('pharma-1'),
        throwsStateError,
      );
      expect(
        () => container.read(repositoryAccessProvider).write('pharma-1'),
        throwsStateError,
      );
    },
  );

  test(
    'Les liens publics restent accessibles mais les routes métier sont bloquées',
    () {
      for (final location in [
        '/ventes',
        '/stock',
        '/configurer',
        '/dashboard',
        '/sauvegardes',
        '/login',
      ]) {
        expect(
          sessionRedirect(
            location: location,
            loading: false,
            hasError: false,
            userId: 'pharma-1',
            emailVerified: false,
            pharmacie: pharmacie(),
          ),
          '/verifier-email',
        );
      }
      for (final location in [
        '/verifier-email',
        '/support',
        '/confidentialite',
        '/suppression-compte',
      ]) {
        expect(
          sessionRedirect(
            location: location,
            loading: false,
            hasError: true,
            userId: 'pharma-1',
            emailVerified: false,
            pharmacie: null,
          ),
          isNull,
        );
      }
    },
  );

  for (final existing in [false, true]) {
    testWidgets(
      'Confirmation puis profil ou activation, ancien compte : $existing',
      (tester) async {
        if (existing) {
          await firestore.doc('pharmacies/pharma-1').set({
            ...pharmacie().toMap(),
            'access_status': 'pending',
          });
        }
        final container = ProviderContainer(
          overrides: [
            firebaseAuthProvider.overrideWithValue(auth),
            firestoreProvider.overrideWithValue(firestore),
            authServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(routerProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VerifyEmailScreen), findsOneWidget);
        expect(auth.user!.sends, 1);
        final check = find.text('J’ai confirmé mon email');
        await tester.ensureVisible(check);
        await tester.pumpAndSettle();
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(find.byType(VerifyEmailScreen), findsOneWidget);
        auth.user!.confirmedRemotely = true;
        await tester.ensureVisible(check);
        await tester.pumpAndSettle();
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(
          find.byType(existing ? AccessScreen : RegisterScreen),
          findsOneWidget,
        );
        expect(auth.user!.forcedToken, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Vérification sur petit écran avec texte agrandi et erreur réseau',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      auth.user!.sendError = FirebaseAuthException(
        code: 'network-request-failed',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(auth.user),
            authServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const VerifyEmailScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Renvoyer le lien'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(auth.user!.emailVerified, isFalse);
      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
