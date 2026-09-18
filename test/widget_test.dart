import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/features/auth/presentation/login_screen.dart';
import 'package:pharmaflow/shared/widgets/pf_button.dart';
import 'package:pharmaflow/shared/widgets/pf_search_bar.dart';

void main() {
  testWidgets('Le login simplifié conserve la récupération du mot de passe', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Première activation'), findsNothing);
    expect(find.text('Créer un compte'), findsOneWidget);
    await tester.ensureVisible(find.text('Mot de passe oublié ?'));
    await tester.tap(find.text('Mot de passe oublié ?'));
    await tester.pumpAndSettle();
    expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
    expect(find.text('Envoyer'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('La recherche affiche les valeurs externes et se réinitialise', (
    tester,
  ) async {
    final query = ValueNotifier('12345');
    addTearDown(query.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: query,
            builder: (context, value, child) => PfSearchBar(
              hint: 'Recherche',
              value: value,
              onChanged: (text) => query.value = text,
            ),
          ),
        ),
      ),
    );
    expect(find.text('12345'), findsOneWidget);
    query.value = '';
    await tester.pump();
    expect(find.text('12345'), findsNothing);
    await tester.enterText(find.byType(TextField), 'produit');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(query.value, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('La connexion exige un email avant tout appel Firebase', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'ancien_pseudo');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('Email valide requis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Un bouton occupé ne déclenche pas une seconde opération', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PfButton(
            label: 'Enregistrer',
            isLoading: true,
            onPressed: () => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    expect(calls, 0);
  });
}
