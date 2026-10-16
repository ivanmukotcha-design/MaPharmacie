import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/config/access_policy.dart';
import 'package:pharmaflow/features/settings/privacy_screen.dart';
import 'package:pharmaflow/services/public_information.dart';

Map<String, dynamic> publicData() => {
  ...jsonDecode(File('admin/public/legal.json').readAsStringSync())
      as Map<String, dynamic>,
  'publisherName': 'Éditeur de test',
  'supportEmail': 'support@example.test',
  'effectiveDate': '2026-10-16',
  'approvedForPublication': true,
};

void main() {
  test('La demande prépare un email sans envoyer ni supprimer de données', () {
    final information = PublicInformation.fromJson(publicData());
    expect(information.ready, isTrue);
    final uri = information.deletionEmail;
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'support@example.test');
    expect(uri.queryParameters['subject'], information.deletionSubject);
    expect(uri.queryParameters['body'], information.deletionBody);
    expect(information.deletionUrl.path, '/suppression-compte.html');
    expect(information.privacyUrl.path, '/confidentialite.html');
  });

  test('Une configuration incomplète ne permet pas une fausse demande', () {
    for (final override in [
      {'approvedForPublication': false},
      {'publisherName': ''},
      {'supportEmail': ''},
      {'supportEmail': 'invalide'},
      {'website': 'http://example.test'},
      {'effectiveDate': ''},
      {'effectiveDate': '2026-02-30'},
      {'sections': <Map<String, String>>[]},
    ]) {
      final information = PublicInformation.fromJson({
        ...publicData(),
        ...override,
      });
      expect(information.ready, isFalse);
      expect(() => information.deletionEmail, throwsStateError);
    }
  });

  test(
    'Les informations publiques restent accessibles sans profil ni session',
    () {
      for (final location in ['/confidentialite', '/suppression-compte']) {
        for (final loading in [false, true]) {
          for (final hasError in [false, true]) {
            for (final userId in [null, 'pending-or-suspended-user']) {
              expect(
                sessionRedirect(
                  location: location,
                  loading: loading,
                  hasError: hasError,
                  userId: userId,
                  emailVerified: false,
                  pharmacie: null,
                ),
                isNull,
              );
            }
          }
        }
      }
      expect(
        sessionRedirect(
          location: '/suppression-compte/autre',
          loading: false,
          hasError: false,
          userId: null,
          emailVerified: false,
          pharmacie: null,
        ),
        '/login',
      );
    },
  );

  testWidgets(
    'Confirmation et repli si aucune messagerie ne peut être ouverte',
    (tester) async {
      Uri? requested;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publicInformationProvider.overrideWith(
              (ref) async => PublicInformation.fromJson(publicData()),
            ),
            publicLinkLauncherProvider.overrideWithValue((uri) async {
              requested = uri;
              return false;
            }),
          ],
          child: const MaterialApp(home: PrivacyScreen(deletion: true)),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('request_account_deletion'));
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Ouverture impossible.'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(requested?.scheme, 'mailto');
      expect(find.textContaining('Ouverture impossible.'), findsOneWidget);
      expect(
        find.textContaining('aucune donnée ne sont effacés'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final deletion in [false, true]) {
    testWidgets('Page publique sur petit écran et texte agrandi : $deletion', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publicInformationProvider.overrideWith(
              (ref) async => PublicInformation.fromJson(publicData()),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: PrivacyScreen(deletion: deletion),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
