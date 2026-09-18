import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../local_database/local_database.dart';
import '../config/auth_provider.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import 'repository_access.dart';

final venteRepositoryProvider = Provider<VenteRepository>((ref) {
  final sync = ref.watch(syncServiceProvider);
  return VenteRepository(
    RepositoryAccess.forRef(ref),
    onChanged: sync.scheduleSync,
    wholesaleAllowed: () => ref.read(wholesaleEnabledProvider),
  );
});

class VenteRepository {
  final RepositoryAccess _access;
  final bool Function() _wholesaleAllowed;
  final Future<Database> Function() _database;
  final void Function()? _onChanged;

  VenteRepository(
    this._access, {
    Future<Database> Function()? database,
    void Function()? onChanged,
    bool Function()? wholesaleAllowed,
  }) : _database = database ?? (() => LocalDatabase.database),
       _onChanged = onChanged,
       _wholesaleAllowed = wholesaleAllowed ?? (() => false);

  Future<void> effectuerVente(VenteModel vente) async {
    _access.write(vente.pharmacieId);
    if (vente.id.isEmpty ||
        vente.items.isEmpty ||
        !['gros', 'detail'].contains(vente.typeVente)) {
      throw const FormatException('Vente invalide.');
    }
    if (vente.items.length > 100) {
      throw StateError('Limitez la vente à 100 produits.');
    }
    final db = await _database();
    await db.transaction((transaction) async {
      _access.write(vente.pharmacieId);
      final existing = await transaction.query(
        'ventes',
        where: 'id = ?',
        whereArgs: [vente.id],
      );
      if (existing.isNotEmpty) {
        final previous = existing.first;
        final rows = await transaction.query(
          'vente_items',
          where: 'vente_id = ?',
          whereArgs: [vente.id],
        );
        final oldItems =
            rows
                .map((row) => jsonEncode(VenteItemModel.fromMap(row).toMap()))
                .toList()
              ..sort();
        final newItems =
            vente.items.map((item) => jsonEncode(item.toMap())).toList()
              ..sort();
        if (previous['pharmacie_id'] != vente.pharmacieId ||
            previous['type_vente'] != vente.typeVente ||
            previous['total_ht'] != vente.totalHT ||
            previous['total_ttc'] != vente.totalTTC ||
            previous['benefice'] != vente.benefice ||
            previous['notes'] != vente.notes ||
            jsonEncode(oldItems) != jsonEncode(newItems)) {
          throw StateError('Identifiant de vente déjà utilisé.');
        }
        return;
      }
      if (vente.typeVente == 'gros' && !_wholesaleAllowed()) {
        throw StateError('Les tarifs de gros sont désactivés.');
      }
      final stockUpdates = <Map<String, dynamic>>[];
      final seen = <String>{};
      var total = 0.0;
      var profit = 0.0;
      for (final item in vente.items) {
        if (!seen.add(item.medicamentId)) {
          throw const FormatException('Produit en double.');
        }
        final rows = await transaction.query(
          'medicaments',
          where: 'id = ? AND pharmacie_id = ? AND est_actif = 1',
          whereArgs: [item.medicamentId, vente.pharmacieId],
        );
        if (rows.isEmpty) {
          throw StateError('Produit introuvable : ${item.medicamentNom}.');
        }
        final med = MedicamentModel.fromSql(rows.first);
        med.validate();
        if (med.estExpire) throw StateError('${med.nom} est expiré.');
        final price = med.prixPourUnite(
          item.unite,
          gros: vente.typeVente == 'gros',
        );
        final cost = med.coutPourUnite(item.unite);
        if (!_same(item.prixUnitaire, price) ||
            !_same(item.prixAchat, cost) ||
            !_same(item.sousTotal, price * item.quantite)) {
          throw StateError(
            'Le prix de ${med.nom} a changé. Recréez le panier.',
          );
        }
        final updated = med.copyWith(
          unites: med.unites.deduire(item.quantite, item.unite),
          revision: med.revision + 1,
        );
        total += item.sousTotal;
        profit += item.beneficeItem;
        await transaction.update(
          'medicaments',
          updated.toSql(),
          where: 'id = ? AND pharmacie_id = ?',
          whereArgs: [med.id, med.pharmacieId],
        );
        stockUpdates.add({
          'id': med.id,
          'document': updated.toMap(),
          'expected_revision': med.revision,
        });
      }
      if (!_same(vente.totalHT, total) ||
          !_same(vente.totalTTC, total) ||
          !_same(vente.benefice, profit)) {
        throw const FormatException('Totaux de vente incohérents.');
      }
      await transaction.insert('ventes', vente.toSql());
      for (var index = 0; index < vente.items.length; index++) {
        await transaction.insert('vente_items', {
          ...vente.items[index].toMap(),
          'id': '${vente.id}_$index',
          'vente_id': vente.id,
        });
      }
      await LocalDatabase.addToSyncQueue(
        executor: transaction,
        collection: 'pharmacies/${vente.pharmacieId}/ventes',
        docId: vente.id,
        operation: 'sale',
        data: {'document': vente.toMap(), 'stock_updates': stockUpdates},
      );
    });
    LocalDatabase.notifyChanged();
    _onChanged?.call();
  }

  bool _same(double first, double second) =>
      first.isFinite && second.isFinite && (first - second).abs() < 0.000001;

  Future<List<VenteModel>> getHistoriqueVentes(String pharmacieId) async {
    _access.read(pharmacieId);
    final db = await _database();
    final rows = await db.query(
      'ventes',
      where: 'pharmacie_id = ?',
      whereArgs: [pharmacieId],
      orderBy: 'date DESC',
    );
    final ventes = <VenteModel>[];
    for (final row in rows) {
      final items = await db.query(
        'vente_items',
        where: 'vente_id = ?',
        whereArgs: [row['id']],
      );
      ventes.add(VenteModel.fromSql(row, items));
    }
    _access.read(pharmacieId);
    return ventes;
  }
}
