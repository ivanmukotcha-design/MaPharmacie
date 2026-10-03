import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/features/auth/presentation/login_screen.dart';
import 'package:pharmaflow/features/auth/presentation/create_account_screen.dart';
import 'package:pharmaflow/features/auth/presentation/register_screen.dart';
import 'package:pharmaflow/features/auth/presentation/access_screen.dart';
import 'package:pharmaflow/features/dashboard/presentation/dashboard_screen.dart';
import 'package:pharmaflow/features/stock/presentation/stock_screen.dart';
import 'package:pharmaflow/features/stock/presentation/medicament_form_screen.dart';
import 'package:pharmaflow/features/stock/presentation/medicament_detail_screen.dart';
import 'package:pharmaflow/features/stock/presentation/lots_screen.dart';
import 'package:pharmaflow/features/sales/presentation/vente_screen.dart';
import 'package:pharmaflow/features/sales/presentation/catalogue_vente.dart';
import 'package:pharmaflow/features/sales/presentation/panier.dart';
import 'package:pharmaflow/features/sales/presentation/historique_ventes_screen.dart';
import 'package:pharmaflow/features/suppliers/presentation/fournisseurs_screen.dart';
import 'package:pharmaflow/features/screens_bundle.dart';
import 'package:pharmaflow/features/settings/backup_screen.dart';
import 'package:pharmaflow/features/settings/sync_screen.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/fournisseur_repository.dart';
import 'package:pharmaflow/services/sync_service.dart';
import 'package:pharmaflow/shared/widgets/sync_banner.dart';
import 'package:pharmaflow/shared/widgets/responsive_layout.dart';
import 'fixtures.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'pharma-1';
  @override
  String get email => 'pharmacie@example.com';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final medicine = MedicamentModel.fromMap({
    ...medicament().toMap(),
    'nom': 'Paracétamol conditionnement familial très grand format 1000 mg',
    'prix_detail': 123456789.0,
  }, 'med-1');
  late Directory directory;
  late Database database;
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('pharmaflow_layout_');
    await databaseFactory.setDatabasesPath(directory.path);
    database = await LocalDatabase.database;
    await database.insert('medicaments', medicine.toSql(synced: true));
    await database.insert('ventes', vente().toSql(synced: true));
  });
  tearDownAll(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  final screens = <String, Widget>{
    'connexion': const LoginScreen(),
    'inscription': const CreateAccountScreen(),
    'profil': const RegisterScreen(),
    'accueil': const DashboardScreen(),
    'acces': const AccessScreen(),
    'stock': const StockScreen(),
    'produit': const MedicamentFormScreen(),
    'detail': const MedicamentDetailScreen(id: 'med-1'),
    'lots': const LotsScreen(id: 'med-1'),
    'ventes': const VenteScreen(),
    'historique': const HistoriqueVentesScreen(),
    'fournisseurs': const FournisseursScreen(),
    'fournisseurs vides': const FournisseursScreen(),
    'rapports': const ReportsScreen(),
    'parametres': const SettingsScreen(),
    'support': const SupportScreen(),
    'sauvegarde': const BackupScreen(),
    'synchronisation': const SyncScreen(),
  };
  final formats = <(String, Size, double)>[
    ('petit', const Size(320, 568), 1),
    ('texte double', const Size(360, 800), 2),
    ('paysage', const Size(640, 360), 1),
    ('tablette', const Size(800, 1280), 1.3),
    ('bureau', const Size(1920, 1080), 1),
    ('clavier', const Size(360, 800), 1.3),
    ('paysage clavier', const Size(640, 360), 1.3),
  ];
  for (final format in formats) {
    for (final screen in screens.entries) {
      testWidgets('${screen.key} / ${format.$1} sans débordement', (
        tester,
      ) async {
        tester.view.physicalSize = format.$2;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (format.$1.contains('clavier')) {
          tester.view.viewInsets = FakeViewPadding(
            bottom: format.$1 == 'clavier' ? 300 : 180,
          );
          addTearDown(tester.view.resetViewInsets);
        }
        final container = ProviderContainer(
          overrides: [
            currentUserProvider.overrideWith((ref) => _User()),
            authStateProvider.overrideWith((ref) => Stream.value(_User())),
            currentPharmacieProvider.overrideWith(
              (ref) => Stream.value(pharmacie()),
            ),
            wholesaleEnabledProvider.overrideWith((ref) => true),
            isOnlineProvider.overrideWithValue(false),
            pendingSyncProvider.overrideWith((ref) async => 1),
            syncStatusProvider.overrideWith(
              (ref) => Stream.value(const SyncStatus()),
            ),
            syncOperationsProvider.overrideWith((ref) async => []),
            dashboardStatsProvider.overrideWith(
              (ref) async => const DashboardStats(
                totalMedicaments: 999999,
                stockFaible: 4,
                enRupture: 1,
                expires: 2,
                expireBientot: 3,
                ventesJour: 123456789,
                beneficesJour: 1234567,
                ventesCount: 1000,
              ),
            ),
            medicamentsProvider.overrideWith((ref) async => [medicine.toSql()]),
            catalogueVenteProvider(
              'pharma-1',
            ).overrideWith((ref) async => [medicine]),
            fournisseursProvider.overrideWith(
              (ref) async => screen.key == 'fournisseurs vides'
                  ? []
                  : [
                      FournisseurModel(
                        id: 'supplier',
                        pharmacieId: 'pharma-1',
                        nom:
                            'Fournisseur au nom particulièrement long pour vérifier les écrans',
                        telephone: '+243123456789',
                        email: '',
                        adresse: '',
                        createdAt: DateTime(2026),
                      ),
                    ],
            ),
            lotsDataProvider('med-1').overrideWith(
              (ref) async => (
                medicine.copyWith(
                  lots: [
                    StockLot(
                      id: 'lot',
                      numero: 'LOT-AVEC-UN-NUMERO-LONG-2026-001',
                      quantiteBase: 100,
                      coutBase: 10,
                      reception: DateTime(2026),
                      expiration: DateTime(2030),
                    ),
                  ],
                ),
                <ActiviteModel>[],
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(currentPharmacieProvider.future);
        if (screen.key == 'ventes') {
          container.read(panierProvider.notifier).ajouterMedicament(medicine);
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(format.$3)),
                child: child!,
              ),
              home: ResponsivePage(child: screen.value),
            ),
          ),
        );
        for (var attempt = 0; attempt < 4; attempt++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen.key == 'ventes') {
          await tester.tap(find.text('Panier (1)').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        for (var step = 0; step < 14; step++) {
          var moved = false;
          for (final element in find.byType(Scrollable).evaluate().toList()) {
            final state = (element as StatefulElement).state as ScrollableState;
            final position = state.position;
            if (position.axis == Axis.vertical &&
                position.hasContentDimensions &&
                position.pixels < position.maxScrollExtent) {
              position.jumpTo(
                (position.pixels + 300).clamp(0, position.maxScrollExtent),
              );
              moved = true;
            }
          }
          if (!moved) break;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final dialogButton = switch (screen.key) {
          'connexion' => 'Mot de passe oublié ?',
          'fournisseurs' => 'Ajouter',
          'sauvegarde' => 'Créer une sauvegarde chiffrée',
          'lots' => 'Réceptionner un lot',
          _ => null,
        };
        if (dialogButton != null) {
          for (final element in find.byType(Scrollable).evaluate().toList()) {
            final position =
                ((element as StatefulElement).state as ScrollableState)
                    .position;
            if (position.axis == Axis.vertical) position.jumpTo(0);
          }
          await tester.pumpAndSettle();
          if (find.text(dialogButton).evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              find.text(dialogButton),
              100,
              scrollable: find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Scrollable &&
                        widget.axisDirection == AxisDirection.down,
                  )
                  .first,
            );
          }
          await tester.ensureVisible(find.text(dialogButton));
          await tester.pumpAndSettle();
          await tester.tap(find.text(dialogButton));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expect(
            find.byType(AlertDialog).evaluate().isNotEmpty ||
                find.byType(BottomSheet).evaluate().isNotEmpty,
            isTrue,
          );
          final dialogFields = find.byType(TextField);
          if (dialogFields.evaluate().isNotEmpty) {
            await tester.ensureVisible(dialogFields.last);
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
            expect(dialogFields.last.hitTestable(), findsOneWidget);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
