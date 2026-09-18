import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/config/router.dart';
import 'package:pharmaflow/features/auth/presentation/login_screen.dart';
import 'package:pharmaflow/features/auth/presentation/register_screen.dart';
import 'fixtures.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  _User(this.uid);
}

void main() {
  test(
    'Les notifications simultanées sont regroupées et annulées après destruction',
    () async {
      final sessions = StreamController<User?>.broadcast(sync: true);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => sessions.stream),
          currentPharmacieProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      final notifierProvider = Provider<RouterNotifier>((ref) {
        final notifier = RouterNotifier(ref);
        ref.onDispose(notifier.dispose);
        return notifier;
      });
      final notifier = container.read(notifierProvider);
      await container.read(currentPharmacieProvider.future);
      await Future<void>.delayed(Duration.zero);
      var notifications = 0;
      notifier.addListener(() => notifications++);
      sessions.add(_User('pharma-1'));
      sessions.add(null);
      expect(notifications, 0);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      sessions.add(_User('pharma-2'));
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      await sessions.close();
    },
  );

  test(
    'Le routeur ne relit pas le graphe pendant une notification Riverpod',
    () async {
      final session = StateProvider<User?>((ref) => null);
      final notifierProvider = Provider<RouterNotifier>((ref) {
        final notifier = RouterNotifier(ref);
        ref.onDispose(notifier.dispose);
        return notifier;
      });
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(ref.watch(session)),
          ),
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(notifierProvider);
      await container.read(authStateProvider.future);
      await container.read(currentPharmacieProvider.future);
      await container.pump();
      var reading = false;
      var notifiedDuringRead = false;
      notifier.addListener(() {
        notifiedDuringRead |= reading;
        container.read(currentPharmacieProvider);
        container.read(currentUserProvider);
      });
      container.read(session.notifier).state = _User('pharma-1');
      reading = true;
      container.read(currentPharmacieProvider);
      reading = false;
      await container.read(authStateProvider.future);
      await container.read(currentPharmacieProvider.future);
      await container.pump();
      expect(notifiedDuringRead, isFalse);
    },
  );

  testWidgets(
    'Les changements de session ne modifient pas les dépendances pendant leur parcours',
    (tester) async {
      final sessions = StreamController<User?>();
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => sessions.stream),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sessions.close);
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      sessions.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      for (var index = 0; index < 4; index++) {
        sessions.add(_User('pharma-$index'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(RegisterScreen), findsOneWidget);
        sessions.add(null);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LoginScreen), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'La création et les mises à jour du profil gardent le routeur stable',
    (tester) async {
      final sessions = StreamController<User?>.broadcast();
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => sessions.stream),
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sessions.close);
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: ValueKey('routing_context'))),
      );
      Future<String> destination() async {
        router.go('/configurer');
        final matches = await router.routeInformationParser
            .parseRouteInformationWithDependencies(
              router.routeInformationProvider.value,
              tester.element(find.byKey(const ValueKey('routing_context'))),
            );
        expect(matches.isError, isFalse);
        return matches.uri.path;
      }

      sessions.add(_User('pharma-1'));
      await tester.pumpAndSettle();
      expect(await destination(), '/configurer');
      await firestore.doc('pharmacies/pharma-1').set(pharmacie().toMap());
      await tester.pumpAndSettle();
      expect(await destination(), '/dashboard');
      expect(identical(container.read(routerProvider), router), isTrue);
      await firestore.doc('pharmacies/pharma-1').update({
        'tarifs_gros_actifs': true,
      });
      await tester.pumpAndSettle();
      expect(await destination(), '/dashboard');
      sessions.add(null);
      await tester.pumpAndSettle();
      expect(await destination(), '/login');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
