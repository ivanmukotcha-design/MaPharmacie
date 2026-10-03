import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/auth_provider.dart';
import 'package:pharmaflow/features/auth/presentation/access_screen.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'fixtures.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'pharma-1';
}

void main() {
  for (final status in ['pending', 'active', 'suspended', 'unknown']) {
    final profile = PharmacieModel.fromMap({
      ...pharmacie().toMap(),
      'access_status': status,
    }, 'pharma-1');
    test('Droits locaux pour $status', () async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => _User()),
          currentPharmacieProvider.overrideWith((ref) => Stream.value(profile)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentPharmacieProvider.future);
      final access = container.read(repositoryAccessProvider);
      if (status == 'active' || status == 'suspended') {
        expect(() => access.read('pharma-1'), returnsNormally);
      } else {
        expect(() => access.read('pharma-1'), throwsStateError);
      }
      expect(
        () => access.write('pharma-1'),
        status == 'active' ? returnsNormally : throwsStateError,
      );
      expect(() => access.read('autre'), throwsStateError);
      expect(() => access.write('autre'), throwsStateError);
    });
    if (status == 'pending' || status == 'suspended') {
      testWidgets('Écran $status sur petit écran avec texte agrandi', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserProvider.overrideWith((ref) => _User()),
              authStateProvider.overrideWith((ref) => Stream.value(_User())),
              currentPharmacieProvider.overrideWith(
                (ref) => Stream.value(profile),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const AccessScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            status == 'pending' ? 'Activation en attente' : 'Compte suspendu',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Sauvegarder mes données locales'),
          status == 'suspended' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
