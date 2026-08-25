import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class ExportService {
  static Future<void> exportStockToExcel(List<MedicamentModel> medicaments) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Stock'];
    
    // En-têtes
    sheet.appendRow([
      TextCellValue('Nom'),
      TextCellValue('Catégorie'),
      TextCellValue('Prix Achat (FC)'),
      TextCellValue('Prix Vente (FC)'),
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
        DoubleCellValue(med.prixGrossiste),
        DoubleCellValue(med.prixDetail),
        IntCellValue(med.unites.totalBoites),
        IntCellValue(med.stockTotal),
        TextCellValue(med.dateExpiration != null 
            ? DateFormat('dd/MM/yyyy').format(med.dateExpiration!) 
            : 'N/A'),
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
      final articlesStr = v.items.map((i) => '${i.medicamentNom} (x${i.quantite})').join(', ');
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
    if (bytes == null) return;

    final directory = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/${fileName}_$timestamp.xlsx');
    
    await file.writeAsBytes(bytes);
    
    await Share.shareXFiles([XFile(file.path)], text: 'Rapport PharmaFlow');
  }
}
