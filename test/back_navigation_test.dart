import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaflow/shared/widgets/main_scaffold.dart';

GoRouter _createRouter({String initialLocation = '/dashboard'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          for (final path in [
            '/dashboard',
            '/stock',
            '/ventes',
            '/rapports',
            '/parametres',
            '/historique-ventes',
            '/fournisseurs',
            '/support',
          ])
            GoRoute(
              path: path,
              builder: (context, state) =>
                  Scaffold(body: Text(path, key: ValueKey(path))),
            ),
        ],
      ),
      for (final path in [
        '/medicament/nouveau',
        '/medicament/:id',
        '/medicament/:id/modifier',
        '/login',
        '/register',
      ])
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(body: Text(state.uri.path)),
        ),
    ],
  );
}

void main() {
  var exitRequests = 0;
  var frameworkHandlesBack = false;

  setUp(() {
    exitRequests = 0;
    frameworkHandlesBack = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exitRequests++;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester, GoRouter router) async {
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        onNavigationNotification: (notification) {
          frameworkHandlesBack = notification.canHandlePop;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('Retour depuis chaque onglet revient à Accueil sans quitter', (
    tester,
  ) async {
    final router = _createRouter();
    await mount(tester, router);

    for (final label in ['Stock', 'Ventes', 'Rapports', 'Paramètres']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack, isTrue);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        isNot('/dashboard'),
      );
      await back(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/dashboard');
      expect(exitRequests, 0);
      expect(frameworkHandlesBack, isFalse);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Les menus ouverts directement reviennent aussi à Accueil', (
    tester,
  ) async {
    final router = _createRouter(initialLocation: '/stock');
    await mount(tester, router);

    for (final path in [
      '/stock',
      '/historique-ventes',
      '/fournisseurs',
      '/support',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(frameworkHandlesBack, isTrue);
      await back(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/dashboard');
      expect(exitRequests, 0);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Retour dépile les fiches et formulaires avant de revenir à Accueil',
    (tester) async {
      final router = _createRouter(initialLocation: '/stock');
      await mount(tester, router);
      unawaited(router.push<void>('/medicament/produit-1'));
      await tester.pumpAndSettle();
      unawaited(router.push<void>('/medicament/produit-1/modifier'));
      await tester.pumpAndSettle();

      await back(tester);
      expect(find.text('/medicament/produit-1'), findsOneWidget);
      await back(tester);
      expect(find.byKey(const ValueKey('/stock')), findsOneWidget);
      unawaited(router.push<void>('/medicament/nouveau'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.byKey(const ValueKey('/stock')), findsOneWidget);
      await back(tester);
      expect(find.byKey(const ValueKey('/dashboard')), findsOneWidget);
      expect(exitRequests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Une page empilée dans le menu revient au menu précédent', (
    tester,
  ) async {
    final router = _createRouter(initialLocation: '/parametres');
    await mount(tester, router);
    unawaited(router.push<void>('/support'));
    await tester.pumpAndSettle();

    await back(tester);
    expect(find.byKey(const ValueKey('/parametres')), findsOneWidget);
    await back(tester);
    expect(find.byKey(const ValueKey('/dashboard')), findsOneWidget);
    expect(exitRequests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final rootNavigator in [true, false]) {
    testWidgets('Retour ferme une boîte de dialogue (racine: $rootNavigator)', (
      tester,
    ) async {
      final router = _createRouter(initialLocation: '/stock');
      await mount(tester, router);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byKey(const ValueKey('/stock'))),
          useRootNavigator: rootNavigator,
          builder: (context) => const AlertDialog(title: Text('Confirmation')),
        ),
      );
      await tester.pumpAndSettle();

      await back(tester);
        expect(find.text('Confirmation'), findsNothing);
        expect(find.byKey(const ValueKey('/stock')), findsOneWidget);
        expect(frameworkHandlesBack, isTrue);
      expect(exitRequests, 0);
      await back(tester);
      expect(find.byKey(const ValueKey('/dashboard')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Retour depuis Accueil conserve la sortie normale', (
    tester,
  ) async {
    final router = _createRouter();
    await mount(tester, router);
    await back(tester);
    expect(exitRequests, 1);
    expect(frameworkHandlesBack, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Après déconnexion, Retour ne ramène pas aux menus protégés', (
    tester,
  ) async {
    final router = _createRouter(initialLocation: '/stock');
    await mount(tester, router);
    router.go('/login');
    await tester.pumpAndSettle();
    expect(frameworkHandlesBack, isFalse);
    unawaited(router.push<void>('/register'));
    await tester.pumpAndSettle();

    await back(tester);
    expect(find.text('/login'), findsOneWidget);
    expect(exitRequests, 0);
    await back(tester);
    expect(find.text('/login'), findsOneWidget);
    expect(exitRequests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
