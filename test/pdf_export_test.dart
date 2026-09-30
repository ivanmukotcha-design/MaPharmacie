import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaflow/models/models.dart';
import 'package:pharmaflow/repositories/repository_access.dart';
import 'package:pharmaflow/services/export_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late RepositoryAccess access;
  final shares = <Map<dynamic, dynamic>>[];
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const sharing = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pharmaflow_pdf_test_');
    shares.clear();
    access = RepositoryAccess((owner, write) {
      if (owner != 'pharma-1') throw StateError('Accès refusé');
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (call) async => directory.path);
    messenger.setMockMethodCallHandler(sharing, (call) async {
      shares.add(Map<dynamic, dynamic>.from(call.arguments as Map));
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(sharing, null);
    await directory.delete(recursive: true);
  });

  Future<String> pdfContent({int index = 0}) async {
    final share = shares[index];
    expect(share['mimeTypes'], ['application/pdf']);
    final path = (share['paths'] as List).single as String;
    expect(path, endsWith('.pdf'));
    expect(path, startsWith(directory.path));
    final bytes = await File(path).readAsBytes();
    final content = latin1.decode(bytes);
    expect(content, startsWith('%PDF-'));
    expect(content.trimRight(), endsWith('%%EOF'));
    expect(content, contains('/FontFile2'));
    expect(content, contains('/ToUnicode'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(content), isNotEmpty);
    return content;
  }

  test(
    'Le stock produit un vrai PDF paginé avec des polices intégrées',
    () async {
      await ExportService.exportStockToPdf(
        List.generate(
          250,
          (index) => MedicamentModel.fromMap({
            ...medicament(id: 'med-$index').toMap(),
            'nom': 'Médicament à cœur $index',
            'categorie': 'Antalgiques',
          }, 'med-$index'),
        ),
        pharmacie: pharmacie(),
        access: access,
        sharePositionOrigin: const Rect.fromLTWH(10, 20, 200, 100),
      );
      final content = await pdfContent();
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(content).length,
        greaterThan(20),
      );
      expect(shares.single['originWidth'], 200);
      expect(shares.single['text'], contains('Pharmacie'));
    },
  );

  test('Les trois rapports vides restent exportables', () async {
    await ExportService.exportStockToPdf(
      [],
      pharmacie: pharmacie(),
      access: access,
    );
    await ExportService.exportVentesToPdf(
      [],
      pharmacie: pharmacie(),
      access: access,
    );
    await ExportService.exportFournisseursToPdf(
      [],
      pharmacie: pharmacie(),
      access: access,
    );
    expect(shares, hasLength(3));
    for (var index = 0; index < shares.length; index++) {
      final content = await pdfContent(index: index);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(content).length, 1);
    }
  });

  test('Le rapport détaille 200 lots sans bloquer la pagination', () async {
    final lots = List.generate(
      200,
      (index) => StockLot(
        id: 'lot-$index',
        numero: 'Lot $index',
        quantiteBase: 1,
        coutBase: 0.5,
        reception: DateTime(2026),
        expiration: DateTime(2030),
      ),
    );
    await ExportService.exportStockToPdf(
      [
        medicament(
          unites: const UnitesStock(comprimes: 200),
        ).copyWith(lots: lots),
        medicament(id: 'empty', unites: const UnitesStock()).copyWith(lots: []),
      ],
      pharmacie: pharmacie(),
      access: access,
    );
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(await pdfContent()).length,
      greaterThan(1),
    );
  });

  test('Une vente de cent articles se répartit sur plusieurs pages', () async {
    await ExportService.exportVentesToPdf(
      [
        vente(
          items: List.generate(100, (index) => venteItem(id: 'article-$index')),
        ),
      ],
      pharmacie: pharmacie(),
      access: access,
    );
    final content = await pdfContent();
    expect(
      RegExp(r'/Type\s*/Page\b').allMatches(content).length,
      greaterThan(1),
    );
    expect((shares.single['paths'] as List).single, contains('Rapport_Ventes'));
  });

  test(
    'Les notes longues des fournisseurs ne bloquent pas la pagination',
    () async {
      await ExportService.exportFournisseursToPdf(
        [
          FournisseurModel(
            id: 'fournisseur-1',
            pharmacieId: 'pharma-1',
            nom: 'Dépôt du cœur',
            telephone: '+243 123456',
            email: 'contact@example.com',
            adresse: 'Rue de la Santé',
            notes: List.filled(300, 'Livraison à vérifier.').join(' '),
            createdAt: DateTime(2025),
          ),
        ],
        pharmacie: pharmacie(),
        access: access,
      );
      final content = await pdfContent();
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(content).length,
        greaterThan(1),
      );
      expect(
        (shares.single['paths'] as List).single,
        contains('Rapport_Fournisseurs'),
      );
    },
  );

  test(
    'Les données étrangères et une session révoquée ne sont pas partagées',
    () async {
      await expectLater(
        ExportService.exportStockToPdf(
          [medicament(pharmacieId: 'autre')],
          pharmacie: pharmacie(),
          access: access,
        ),
        throwsStateError,
      );
      await expectLater(
        ExportService.exportVentesToPdf(
          [vente(pharmacieId: 'autre')],
          pharmacie: pharmacie(),
          access: access,
        ),
        throwsStateError,
      );
      var checks = 0;
      final revoked = RepositoryAccess((owner, write) {
        if (++checks >= 3) throw StateError('Session fermée');
      });
      await expectLater(
        ExportService.exportStockToPdf(
          [medicament()],
          pharmacie: pharmacie(),
          access: revoked,
        ),
        throwsStateError,
      );
      expect(shares, isEmpty);
      expect(await directory.list().toList(), isEmpty);
    },
  );
}
