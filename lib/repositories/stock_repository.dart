import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../local_database/local_database.dart';
import '../models/models.dart';
import '../services/sync_service.dart';
import 'repository_access.dart';
import 'stock_movement.dart';
import 'sync_write_guard.dart';

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(
    RepositoryAccess.forRef(ref),
    onChanged: ref.watch(syncServiceProvider).scheduleSync,
  ),
);

class StockRepository {
  final RepositoryAccess _access;
  final Future<Database> Function() _database;
  final void Function()? _onChanged;
  StockRepository(
    this._access, {
    Future<Database> Function()? database,
    void Function()? onChanged,
  }) : _database = database ?? (() => LocalDatabase.database),
       _onChanged = onChanged;

  Future<void> activate(MedicamentModel expected) => _change(
    expected,
    'initial',
    'Activation du suivi par lots',
    (current) {
      if (current.suiviLots) {
        throw StateError('Le suivi par lots est déjà activé.');
      }
      final lots = <StockLot>[];
      if (current.stockTotal > 0) {
        if (current.prixAchat == null) {
          throw StateError(
            'Renseignez le prix d’achat avant d’activer le suivi.',
          );
        }
        lots.add(
          StockLot(
            id: const Uuid().v4(),
            numero: 'Stock initial',
            quantiteBase: current.stockTotal,
            coutBase:
                current.prixAchat! / current.unites.facteur(current.unitePrix),
            reception: DateTime.now(),
            expiration: current.dateExpiration,
            fournisseur: current.fournisseurNom,
          ),
        );
      }
      return lots;
    },
  );

  Future<void> receive(MedicamentModel expected, StockLot lot) {
    lot.validate();
    if (lot.quantiteBase <= 0 ||
        lot.expiration == null ||
        lot.expiredAt(DateTime.now())) {
      throw const FormatException(
        'Renseignez une quantité positive et une date de péremption non passée.',
      );
    }
    return _change(expected, 'reception', 'Réception du lot ${lot.numero}', (
      current,
    ) {
      if (!current.suiviLots) {
        throw StateError('Activez d’abord le suivi par lots.');
      }
      if (current.lots!.any((entry) => entry.id == lot.id)) {
        throw StateError('Ce lot existe déjà.');
      }
      return [...current.lots!.where((entry) => entry.quantiteBase > 0), lot];
    }, lotId: lot.id);
  }

  Future<void> adjust(
    MedicamentModel expected,
    String lotId,
    int quantity,
    String reason,
  ) {
    if (quantity < 0 || reason.trim().isEmpty || reason.trim().length > 300) {
      throw const FormatException(
        'Quantité positive ou nulle et motif requis (300 caractères maximum).',
      );
    }
    return _change(expected, 'correction', reason.trim(), (current) {
      if (!current.suiviLots ||
          !current.lots!.any((entry) => entry.id == lotId)) {
        throw StateError('Lot introuvable.');
      }
      final previous = current.lots!.singleWhere((entry) => entry.id == lotId);
      if (previous.quantiteBase == quantity) {
        throw StateError('La quantité n’a pas changé.');
      }
      return current.lots!
          .map(
            (entry) => entry.id == lotId ? entry.withQuantity(quantity) : entry,
          )
          .toList();
    }, lotId: lotId);
  }

  Future<void> _change(
    MedicamentModel expected,
    String kind,
    String reason,
    List<StockLot> Function(MedicamentModel) change, {
    String? lotId,
  }) async {
    _access.write(expected.pharmacieId);
    final db = await _database();
    await db.transaction((transaction) async {
      _access.write(expected.pharmacieId);
      await ensureNoSyncIssue(transaction, expected.pharmacieId, {
        'medicaments/${expected.id}',
      });
      final rows = await transaction.query(
        'medicaments',
        where: 'id = ? AND pharmacie_id = ? AND est_actif = 1',
        whereArgs: [expected.id, expected.pharmacieId],
      );
      if (rows.isEmpty) throw StateError('Produit introuvable.');
      final current = MedicamentModel.fromSql(rows.single)..validate();
      if (current.revision != expected.revision) {
        throw StateError('Le stock a changé. Rechargez cette page.');
      }
      final lots = change(current);
      final updated = current.copyWith(
        lots: lots,
        revision: current.revision + 1,
        unites: current.unites.avecTotalBase(
          lots.fold(0, (total, lot) => total + lot.quantiteBase),
          flacon: current.unitePrix == 'flacon',
        ),
      )..validate();
      final movement = stockMovement(
        updated,
        before: current.stockTotal,
        kind: kind,
        reason: reason,
        lotId: lotId,
      );
      await transaction.update(
        'medicaments',
        updated.toSql(),
        where: 'id = ? AND pharmacie_id = ?',
        whereArgs: [current.id, current.pharmacieId],
      );
      await transaction.insert('activites', movement.toSql());
      await LocalDatabase.addToSyncQueue(
        executor: transaction,
        collection: 'pharmacies/${current.pharmacieId}/medicaments',
        docId: current.id,
        operation: 'set',
        data: {
          'document': updated.toMap(),
          'expected_revision': current.revision,
          'activities': [movementPayload(movement)],
        },
      );
    });
    LocalDatabase.notifyChanged();
    _onChanged?.call();
  }

  Future<List<ActiviteModel>> movements(String owner, String medicineId) async {
    _access.read(owner);
    final db = await _database();
    final rows = await db.query(
      'activites',
      where: 'pharmacie_id = ? AND type = ?',
      whereArgs: [owner, 'mouvement_stock'],
      orderBy: 'date DESC',
    );
    _access.read(owner);
    return rows
        .map(ActiviteModel.fromSql)
        .where((entry) => entry.metadata?['medicament_id'] == medicineId)
        .toList();
  }
}
