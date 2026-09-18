import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../local_database/local_database.dart';
import '../repositories/repository_access.dart';
import 'package:intl/intl.dart';

class ExportService {
  static Future<void> exportStockToExcel(
    List<MedicamentModel> medicaments,
  ) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Stock'];

    // En-têtes
    sheet.appendRow([
      TextCellValue('Nom'),
      TextCellValue('Catégorie'),
      TextCellValue('Prix Achat (FC)'),
      TextCellValue('Prix Gros (FC)'),
      TextCellValue('Prix Détail (FC)'),
      TextCellValue('Unité des prix'),
      TextCellValue('Stock (Boîtes)'),
      TextCellValue('Stock (Total Unités)'),
      TextCellValue('Date Expiration'),
      TextCellValue('Fournisseur'),
    ]);

    // Données
    for (final med in medicaments) {
      sheet.appendRow([
        TextCellValue(med.nom),
        TextCellValue(med.categorie),
        med.prixAchat == null
            ? TextCellValue('Non renseigné')
            : DoubleCellValue(med.prixAchat!),
        med.prixGrossiste == null
            ? TextCellValue('Non renseigné')
            : DoubleCellValue(med.prixGrossiste!),
        DoubleCellValue(med.prixDetail),
        TextCellValue(med.unitePrix),
        IntCellValue(med.unites.totalBoites),
        IntCellValue(med.stockTotal),
        TextCellValue(
          med.dateExpiration != null
              ? DateFormat('dd/MM/yyyy').format(med.dateExpiration!)
              : 'N/A',
        ),
        TextCellValue(med.fournisseurNom),
      ]);
    }

    await _saveAndShare(excel, 'Export_Stock');
  }

  static Future<void> exportVentesToExcel(List<VenteModel> ventes) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Ventes'];

    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Type'),
      TextCellValue('Total TTC (FC)'),
      TextCellValue('Bénéfice (FC)'),
      TextCellValue('Articles'),
    ]);

    for (final v in ventes) {
      final articlesStr = v.items
          .map(
            (i) =>
                '${i.medicamentNom} (${i.quantite} ${i.unite}, ${i.prixUnitaire} FC)',
          )
          .join(', ');
      sheet.appendRow([
        TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(v.date)),
        TextCellValue(v.typeVente),
        DoubleCellValue(v.totalTTC),
        DoubleCellValue(v.benefice),
        TextCellValue(articlesStr),
      ]);
    }

    await _saveAndShare(excel, 'Export_Ventes');
  }

  static Future<void> _saveAndShare(Excel excel, String fileName) async {
    final bytes = excel.encode();
    if (bytes == null) throw StateError('Impossible de générer le classeur');

    final directory = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/${fileName}_$timestamp.xlsx');

    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: 'Rapport PharmaFlow');
  }

  static Future<void> exportFournisseursToExcel(
    List<FournisseurModel> suppliers,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Fournisseurs'];
    sheet.appendRow(
      [
        'Nom',
        'Téléphone',
        'Email',
        'Adresse',
        'Notes',
      ].map(TextCellValue.new).toList(),
    );
    for (final supplier in suppliers) {
      sheet.appendRow(
        [
          supplier.nom,
          supplier.telephone,
          supplier.email,
          supplier.adresse,
          supplier.notes ?? '',
        ].map(TextCellValue.new).toList(),
      );
    }
    await _saveAndShare(excel, 'Export_Fournisseurs');
  }

  static Future<void> backup(String owner, RepositoryAccess access) async {
    access.check(owner, false);
    final db = await LocalDatabase.database;
    final data = await db.transaction((transaction) async {
      access.check(owner, false);
      final tables = <String, dynamic>{};
      for (final table in [
        'medicaments',
        'fournisseurs',
        'ventes',
        'activites',
        'sync_queue',
      ]) {
        tables[table] = await transaction.query(
          table,
          where: 'pharmacie_id = ?',
          whereArgs: [owner],
        );
      }
      tables['vente_items'] = await transaction.rawQuery(
        'SELECT items.* FROM vente_items items JOIN ventes ON ventes.id = items.vente_id WHERE ventes.pharmacie_id = ?',
        [owner],
      );
      return {
        'format_version': 1,
        'schema_version': 2,
        'pharmacie_id': owner,
        'exported_at': DateTime.now().toIso8601String(),
        'tables': tables,
      };
    });
    access.check(owner, false);
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/PharmaFlow_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(data));
    access.check(owner, false);
    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Sauvegarde confidentielle PharmaFlow');
  }
}
