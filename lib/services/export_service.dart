import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../repositories/repository_access.dart';

class ExportService {
  static Future<void> exportStockToPdf(
    List<MedicamentModel> medicaments, {
    required PharmacieModel pharmacie,
    required RepositoryAccess access,
    String titre = 'Liste complète des médicaments',
    Rect? sharePositionOrigin,
  }) async {
    _checkOwners(
      medicaments.map((medicament) => medicament.pharmacieId),
      pharmacie,
      access,
    );
    final document = await _document(pharmacie, titre, [
      pw.Text('Nombre de produits : ${medicaments.length}'),
      pw.SizedBox(height: 12),
      if (medicaments.isEmpty)
        pw.Text('Aucun médicament ne correspond à ce rapport.')
      else
        _table(
          [
            'Médicament / Catégorie',
            'Stock physique / vendable',
            'Prix (FC)',
            'Expiration / État',
            'Fournisseur',
          ],
          medicaments
              .map(
                (medicament) => [
                  '${medicament.nom}\n${medicament.categorie}',
                  '${medicament.unites.affichage}\nTotal : ${medicament.stockTotal} ${medicament.unitePrix == 'flacon' ? 'flacons' : 'comprimés'}${medicament.suiviLots ? '\nVendable : ${medicament.unitesVendables.totalUniteBase}' : ''}',
                  'Unité : ${_unite(medicament.unitePrix)}\nAchat : ${_montant(medicament.prixAchat)}\nGros : ${_montant(medicament.prixGrossiste)}\nDétail : ${_montant(medicament.prixDetail)}',
                  '${medicament.dateExpiration == null ? 'Non renseignée' : DateFormat('dd/MM/yyyy').format(medicament.dateExpiration!)}\n${_etat(medicament)}',
                  medicament.fournisseurNom,
                ],
              )
              .toList(),
        ),
      for (final medicine in medicaments.where((entry) => entry.suiviLots)) ...[
        pw.SizedBox(height: 12),
        pw.Text(
          'Lots : ${medicine.nom} — quantités et coûts par unité de base',
        ),
        _table(
          ['Lot', 'Quantité', 'Achat (FC)', 'Péremption', 'Fournisseur'],
          [
            for (final lot in medicine.lots!)
              [
                lot.numero,
                '${lot.quantiteBase}',
                _montant(lot.coutBase),
                lot.expiration == null
                    ? 'Inconnue'
                    : '${DateFormat('dd/MM/yyyy').format(lot.expiration!)}${lot.expiredAt(DateTime.now()) ? ' (expiré)' : ''}',
                lot.fournisseur,
              ],
          ],
        ),
      ],
    ]);
    await _saveAndSharePdf(
      document,
      'Rapport_Stock',
      pharmacie,
      access,
      sharePositionOrigin,
    );
  }

  static Future<void> exportVentesToPdf(
    List<VenteModel> ventes, {
    required PharmacieModel pharmacie,
    required RepositoryAccess access,
    Rect? sharePositionOrigin,
  }) async {
    _checkOwners(ventes.map((vente) => vente.pharmacieId), pharmacie, access);
    final ordered = [...ventes]
      ..sort((first, second) => second.date.compareTo(first.date));
    final total = ventes.fold(
      0.0,
      (montant, vente) => montant + vente.totalTTC,
    );
    final benefice = ventes.fold(
      0.0,
      (montant, vente) => montant + vente.benefice,
    );
    final document = await _document(pharmacie, 'Historique des ventes', [
      pw.Text('Nombre de ventes : ${ventes.length}'),
      pw.Text(
        "Chiffre d'affaires : ${_montant(total)} FC | Bénéfice : ${_montant(benefice)} FC",
      ),
      if (ordered.isNotEmpty)
        pw.Text(
          'Période : ${DateFormat('dd/MM/yyyy').format(ordered.last.date)} au ${DateFormat('dd/MM/yyyy').format(ordered.first.date)}',
        ),
      pw.SizedBox(height: 12),
      if (ventes.isEmpty) pw.Text('Aucune vente enregistrée.'),
      for (final vente in ordered) ...[
        _table(
          ['Vente', 'Date', 'Type', 'Total TTC (FC)', 'Bénéfice (FC)'],
          [
            [
              vente.id,
              DateFormat('dd/MM/yyyy HH:mm').format(vente.date),
              vente.typeVente == 'gros' ? 'Gros' : 'Détail',
              _montant(vente.totalTTC),
              _montant(vente.benefice),
            ],
          ],
        ),
        _table(
          [
            'Produit',
            'Quantité',
            'Unité',
            'Prix unitaire (FC)',
            'Sous-total (FC)',
          ],
          vente.items
              .map(
                (item) => [
                  item.medicamentNom,
                  item.quantite.toString(),
                  _unite(item.unite),
                  _montant(item.prixUnitaire),
                  _montant(item.sousTotal),
                ],
              )
              .toList(),
        ),
        if (vente.notes?.isNotEmpty == true)
          _table(
            ['Notes'],
            [
              [vente.notes!],
            ],
          ),
        pw.SizedBox(height: 16),
      ],
    ]);
    await _saveAndSharePdf(
      document,
      'Rapport_Ventes',
      pharmacie,
      access,
      sharePositionOrigin,
    );
  }

  static Future<void> exportFournisseursToPdf(
    List<FournisseurModel> fournisseurs, {
    required PharmacieModel pharmacie,
    required RepositoryAccess access,
    Rect? sharePositionOrigin,
  }) async {
    _checkOwners(
      fournisseurs.map((fournisseur) => fournisseur.pharmacieId),
      pharmacie,
      access,
    );
    final document = await _document(pharmacie, 'Liste des fournisseurs', [
      pw.Text('Nombre de fournisseurs : ${fournisseurs.length}'),
      pw.SizedBox(height: 12),
      if (fournisseurs.isEmpty)
        pw.Text('Aucun fournisseur enregistré.')
      else
        _table(
          ['Nom', 'Téléphone', 'Email', 'Adresse', 'Notes'],
          fournisseurs
              .map(
                (fournisseur) => [
                  fournisseur.nom,
                  fournisseur.telephone,
                  fournisseur.email,
                  fournisseur.adresse,
                  fournisseur.notes ?? '',
                ],
              )
              .toList(),
        ),
    ]);
    await _saveAndSharePdf(
      document,
      'Rapport_Fournisseurs',
      pharmacie,
      access,
      sharePositionOrigin,
    );
  }

  static void _checkOwners(
    Iterable<String> owners,
    PharmacieModel pharmacie,
    RepositoryAccess access,
  ) {
    access.read(pharmacie.id);
    if (owners.any((owner) => owner != pharmacie.id)) {
      throw StateError(
        'Ce rapport contient des données d’une autre pharmacie.',
      );
    }
  }

  static String _montant(double? value) =>
      value == null ? 'Non renseigné' : value.toStringAsFixed(2);

  static String _unite(String unite) => switch (unite) {
    'boite' => 'boîte',
    'comprimes' => 'comprimé',
    _ => unite,
  };

  static String _etat(MedicamentModel medicament) {
    if (medicament.suiviLots && medicament.contientExpires) {
      return 'Contient des lots expirés';
    }
    if (medicament.estExpire) return 'Expiré';
    if (medicament.expireBientot) return 'Expiration proche';
    if (medicament.estEnRupture) return 'Rupture';
    if (medicament.estStockFaible) return 'Stock faible';
    return 'Disponible';
  }

  static pw.Table _table(List<String> headers, List<List<String>> rows) {
    final data = <List<String>>[];
    for (final row in rows) {
      final cells = row.map((cell) => cell.runes.toList()).toList();
      final parts = cells.fold(1, (count, cell) {
        final required = (cell.length + 159) ~/ 160;
        return required > count ? required : count;
      });
      for (var part = 0; part < parts; part++) {
        data.add([
          for (final cell in cells)
            String.fromCharCodes(cell.skip(part * 160).take(160)),
        ]);
      }
    }
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      defaultColumnWidth: const pw.FlexColumnWidth(),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      headerAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.all(6),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  static Future<pw.Document> _document(
    PharmacieModel pharmacie,
    String titre,
    List<pw.Widget> body,
  ) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-bold.ttf'),
    );
    final generated = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final document = pw.Document(
      title: titre,
      author: pharmacie.nom,
      creator: 'Ma Pharmacie',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        maxPages: body.fold<int>(
          20,
          (count, widget) =>
              count + (widget is pw.Table ? widget.children.length : 1),
        ),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                pharmacie.nom,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(titre, style: const pw.TextStyle(fontSize: 13)),
              pw.Text(
                'Édité le $generated - Données présentes sur cet appareil',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Rapport confidentiel - ${pharmacie.nom}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
        build: (context) => body,
      ),
    );
    return document;
  }

  static Future<void> _saveAndSharePdf(
    pw.Document document,
    String fileName,
    PharmacieModel pharmacie,
    RepositoryAccess access,
    Rect? sharePositionOrigin,
  ) async {
    access.read(pharmacie.id);
    final bytes = await document.save();
    access.read(pharmacie.id);
    final directory = await getTemporaryDirectory();
    access.read(pharmacie.id);
    final file = File(
      '${directory.path}/${fileName}_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    access.read(pharmacie.id);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'Rapport confidentiel - ${pharmacie.nom}',
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
