import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/features/settings/sync_screen.dart';
import 'package:pharmaflow/local_database/local_database.dart';
import 'package:pharmaflow/local_database/sync_codec.dart';
import 'package:pharmaflow/services/sync_operation.dart';
import 'package:pharmaflow/services/sync_service.dart';
import 'fixtures.dart';

class _Sync extends Fake implements SyncService {
  final SyncOperation operation;
  int confirmations = 0;
  bool fail = false;
  _Sync(this.operation);
  @override
  Future<List<SyncOperation>> pendingOperations() async =>
      confirmations == 0 ? [operation] : [];
  @override
  Future<SaleReconciliation> previewSaleReconciliation(int id) async {
    if (fail) throw StateError('Stock insuffisant sur le serveur.');
    return SaleReconciliation(operation, [medicament()]);
  }

  @override
  Future<void> reconcileSale(SaleReconciliation preview) async {
    confirmations++;
  }
}

void main() {
  late _Sync sync;
  late ProviderContainer container;
  setUp(() {
    sync = _Sync(
      SyncOperation({
        'id': 1,
        'pharmacie_id': 'pharma-1',
        'collection': 'pharmacies/pharma-1/ventes',
        'doc_id': 'sale-1',
        'operation_id': 'operation-1',
        'operation': 'sale',
        'last_error': 'Conflit entre appareils.',
        'data': SyncCodec.encode({
          'document': vente().toMap(),
          'stock_updates': [],
        }),
      }),
    );
    container = ProviderContainer(
      overrides: [
        syncServiceProvider.overrideWithValue(sync),
        syncStatusProvider.overrideWith((ref) => const Stream.empty()),
        localChangesProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SyncScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Une vente n’est rapprochée qu’après lecture et confirmation de l’aperçu',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Vérifier et rapprocher la vente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Stock serveur : 10 boîtes'), findsOneWidget);
      expect(
        find.textContaining('Après rapprochement : 8 boîtes'),
        findsOneWidget,
      );
      expect(sync.confirmations, 0);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(sync.confirmations, 0);
      await tester.tap(find.text('Vérifier et rapprocher la vente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirmer'));
      await tester.pumpAndSettle();
      expect(sync.confirmations, 1);
      expect(find.text('Aucune opération en attente.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Un refus est explicite et ne propose aucune confirmation', (
    tester,
  ) async {
    sync.fail = true;
    await mount(tester);
    await tester.tap(find.text('Vérifier et rapprocher la vente'));
    await tester.pumpAndSettle();
    expect(find.text('Stock insuffisant sur le serveur.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sync.confirmations, 0);
    expect(tester.takeException(), isNull);
  });
}
