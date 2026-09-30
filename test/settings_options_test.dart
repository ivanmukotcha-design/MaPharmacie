import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/features/settings/settings_screen.dart';
import 'package:pharmaflow/features/settings/backup_screen.dart';
import 'package:pharmaflow/services/pharmacie_settings_service.dart';
import 'package:pharmaflow/services/sync_service.dart';
import 'package:pharmaflow/shared/widgets/sync_banner.dart';
import 'package:pharmaflow/shared/widgets/wholesale_setting.dart';
import 'fixtures.dart';

class _Settings extends Fake implements PharmacieSettingsService {
  final void Function(String, bool) enregistrer;
  _Settings(this.enregistrer);
  @override
  Future<void> setWholesaleEnabled(String pharmacieId, bool enabled) async =>
      enregistrer(pharmacieId, enabled);
}

void main() {
  late ProviderContainer container;
  final wholesale = StateProvider<bool>((ref) => false);
  setUp(() {
    container = ProviderContainer(
      overrides: [
        currentPharmacieProvider.overrideWith(
          (ref) => Stream.value(pharmacie()),
        ),
        wholesaleEnabledProvider.overrideWith((ref) => ref.watch(wholesale)),
        pendingSyncProvider.overrideWith((ref) async => 0),
        syncStatusProvider.overrideWith((ref) => const Stream.empty()),
        pharmacieSettingsServiceProvider.overrideWithValue(
          _Settings((owner, enabled) {
            expect(owner, 'pharma-1');
            container.read(wholesale.notifier).state = enabled;
          }),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  testWidgets('Les tarifs restent facultatifs et modifiables explicitement', (
    tester,
  ) async {
    await container.read(currentPharmacieProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: WholesaleSetting())),
      ),
    );
    expect(find.text('Tarifs de gros (facultatif)'), findsOneWidget);
    expect(
      find.textContaining(
        'La vente par carton reste possible sans cette option.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Les options avancées ouvrent la sauvegarde chiffrée avec un retour aux paramètres',
    (tester) async {
      await container.read(currentPharmacieProvider.future);
      final router = GoRouter(
        initialLocation: '/parametres',
        routes: [
          GoRoute(
            path: '/parametres',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/sauvegardes',
            builder: (_, __) => const BackupScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Options avancées'), 200);
      final advanced = find
          .ancestor(
            of: find.text('Options avancées'),
            matching: find.byType(Column),
          )
          .first;
      expect(
        find.descendant(
          of: advanced,
          matching: find.byKey(const ValueKey('settings_backup')),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings_backup')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('settings_backup')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Créer une sauvegarde chiffrée'),
        200,
      );
      expect(find.text('Créer une sauvegarde chiffrée'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Restaurer une sauvegarde'),
        100,
      );
      expect(find.text('Restaurer une sauvegarde'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/parametres');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
