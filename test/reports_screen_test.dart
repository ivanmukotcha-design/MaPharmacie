import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/features/reports/reports_screen.dart';
import 'package:pharmaflow/features/support/support_screen.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/medicament_repository.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/services/public_information.dart';

import 'fixtures.dart';

class _Medicaments extends Fake implements MedicamentRepository {
  int calls = 0;
  var request = Completer<List<MedicamentModel>>();

  @override
  Future<List<MedicamentModel>> getMedicaments(String pharmacieId) {
    calls++;
    return request.future;
  }
}

void main() {
  testWidgets(
    'Les rapports proposent uniquement le PDF et empêchent les doubles exports',
    (tester) async {
      final repository = _Medicaments();
      final container = ProviderContainer(
        overrides: [
          currentPharmacieProvider.overrideWith(
            (ref) => Stream.value(pharmacie()),
          ),
          medicamentRepositoryProvider.overrideWithValue(repository),
          repositoryAccessProvider.overrideWithValue(
            RepositoryAccess((owner, write) {}),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentPharmacieProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ReportsScreen()),
        ),
      );
      expect(find.text('PDF'), findsWidgets);
      expect(find.text('Excel'), findsNothing);
      await tester.tap(find.text('PDF').first);
      await tester.pump();
      expect(find.text('Préparation du rapport PDF...'), findsOneWidget);
      await tester.tap(find.text('PDF').first);
      expect(repository.calls, 1);
      repository.request.completeError(StateError('Erreur technique de test'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Impossible de générer ou partager le PDF. Veuillez réessayer.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Erreur technique de test'), findsNothing);
      repository.request = Completer<List<MedicamentModel>>();
      await tester.tap(find.text('PDF').first);
      expect(repository.calls, 2);
      repository.request.completeError(StateError('Nouvelle erreur'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('L’aide explique le partage du PDF', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(publicInformationProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SupportScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Comment exporter mes rapports ?'),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comment exporter mes rapports ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('puis PDF'), findsOneWidget);
    expect(find.textContaining('puis Excel'), findsNothing);
  });
}
