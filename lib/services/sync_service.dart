import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../config/auth_provider.dart';
import '../local_database/local_database.dart';
import '../local_database/sync_codec.dart';
import '../models/models.dart';
import '../core/errors/user_message.dart';
import 'sync_operation.dart';

class SaleReconciliation {
  final SyncOperation operation;
  final List<MedicamentModel> stocks;
  final bool alreadySent;
  SaleReconciliation(this.operation, this.stocks, {this.alreadySent = false});
  VenteModel get sale =>
      VenteModel.fromMap(operation.document, operation.documentId);
}

class SyncStatus {
  final bool running;
  final String? error;
  const SyncStatus({this.running = false, this.error});
}

class SyncService {
  final FirebaseFirestore _firestore;
  final String? pharmacieId;
  final bool Function() _sessionValid;
  final bool Function() _canWrite;
  final Future<bool> Function() _isConnected;
  final Future<Database> Function() _database;
  final _statusController = StreamController<SyncStatus>.broadcast();
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  Timer? _timer;
  Timer? _scheduled;
  Future<void>? _inFlight;
  bool _disposed = false;
  SyncStatus status = const SyncStatus();

  SyncService(
    this._firestore, {
    required this.pharmacieId,
    required bool Function() sessionValid,
    required bool Function() canWrite,
    Future<bool> Function()? isConnected,
    Future<Database> Function()? database,
  }) : _sessionValid = sessionValid,
       _canWrite = canWrite,
       _isConnected =
           isConnected ??
           (() async =>
               await Connectivity().checkConnectivity() !=
               ConnectivityResult.none),
       _database = database ?? (() => LocalDatabase.database);

  Stream<SyncStatus> get statuses async* {
    yield status;
    yield* _statusController.stream;
  }

  void init() {
    if (pharmacieId == null) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) scheduleSync();
    });
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => scheduleSync());
    scheduleSync();
  }

  void scheduleSync() {
    if (_disposed || pharmacieId == null) return;
    _scheduled?.cancel();
    _scheduled = Timer(const Duration(milliseconds: 300), () async {
      try {
        await sync();
      } catch (_) {}
    });
  }

  Future<void> sync() {
    return _exclusive(_synchronize);
  }

  Future<void> _exclusive(Future<void> Function() action) {
    if (_inFlight != null) return _inFlight!;
    final completer = Completer<void>();
    _inFlight = completer.future;
    action()
        .then(completer.complete, onError: completer.completeError)
        .whenComplete(() {
          _inFlight = null;
        });
    return completer.future;
  }

  void _assertSession() {
    if (_disposed || pharmacieId == null || !_sessionValid()) {
      throw StateError('La session a changé. Synchronisation interrompue.');
    }
  }

  void _emit(SyncStatus value) {
    if (_disposed) return;
    status = value;
    _statusController.add(value);
  }

  Future<void> _synchronize() async {
    try {
      _assertSession();
      if (!await _isConnected()) {
        throw StateError('Hors ligne : données conservées sur cet appareil.');
      }
      _assertSession();
      _emit(const SyncStatus(running: true));
      final db = await _database();
      final pending = await LocalDatabase.getPendingSync(
        pharmacieId!,
        executor: db,
      );
      if (pending.isNotEmpty && !_canWrite()) {
        throw StateError(
          'Des modifications attendent une autorisation d’accès à votre pharmacie.',
        );
      }
      final blocked = <String>{};
      var failures = 0;
      for (final item in pending) {
        _assertSession();
        SyncOperation? operation;
        try {
          operation = SyncOperation(item);
          operation.validate(pharmacieId!);
          if (operation.overlaps(blocked)) {
            blocked.addAll(operation.affected);
            continue;
          }
          await _push(item);
          _assertSession();
          await _acknowledge(db, item);
        } catch (error) {
          _assertSession();
          if (error is FirebaseException) rethrow;
          blocked.addAll(operation?.affected ?? {'*'});
          failures++;
          await db.rawUpdate(
            'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? WHERE id = ? AND pharmacie_id = ?',
            [userMessage(error), item['id'], pharmacieId],
          );
        }
      }
      _assertSession();
      await _pull(db);
      if (failures > 0) {
        throw StateError(
          '$failures opération(s) nécessitent une vérification. '
          'Les opérations indépendantes ont été traitées. Consultez le suivi de synchronisation.',
        );
      }
      _emit(const SyncStatus());
    } catch (error) {
      _emit(SyncStatus(error: userMessage(error)));
      rethrow;
    } finally {
      LocalDatabase.notifyChanged();
    }
  }

  Future<void> _push(
    Map<String, dynamic> item, {
    SaleReconciliation? reconciliation,
  }) async {
    final operation = SyncOperation(item)..validate(pharmacieId!);
    final collection = item['collection'] as String;
    final table = collection.split('/').last;
    if (collection != 'pharmacies/$pharmacieId/$table' ||
        !['medicaments', 'fournisseurs', 'ventes'].contains(table)) {
      throw StateError('Opération étrangère à cette pharmacie.');
    }
    if (item['operation'] == 'legacy') {
      throw StateError(item['last_error'] as String);
    }
    final data = SyncCodec.decode(item['data'] as String);
    final document = Map<String, dynamic>.from(data['document'] as Map);
    if (document['pharmacie_id'] != pharmacieId) {
      throw StateError('Pharmacie incohérente.');
    }
    final operationId = item['operation_id'] as String;
    final reference = _firestore
        .collection(collection)
        .doc(item['doc_id'] as String);
    final receiptRef = _firestore.doc(
      'pharmacies/$pharmacieId/activites/sync_$operationId',
    );
    await _firestore.runTransaction((transaction) async {
      _assertSession();
      if (!_canWrite()) throw StateError('La pharmacie est en lecture seule.');
      final receipt = await transaction.get(receiptRef);
      if (receipt.exists) {
        if (receipt.data()?['fingerprint'] != operation.fingerprint ||
            receipt.data()?['collection'] != collection ||
            receipt.data()?['doc_id'] != operation.documentId) {
          throw StateError(
            'Cette opération a déjà été envoyée avec un autre contenu. Contactez le support.',
          );
        }
        return;
      }
      final remote = await transaction.get(reference);
      if (remote.data()?['_operation_id'] == operationId) return;
      if (item['operation'] == 'sale') {
        if (remote.exists) {
          throw StateError('Une autre vente utilise cet identifiant.');
        }
        final updates = (data['stock_updates'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
        final references = <DocumentReference<Map<String, dynamic>>>[];
        final documents = <Map<String, dynamic>>[];
        final sale = VenteModel.fromMap(document, operation.documentId);
        if (sale.items.length != updates.length ||
            sale.items.map((entry) => entry.medicamentId).toSet().length !=
                sale.items.length) {
          throw const FormatException('Articles de vente incohérents.');
        }
        for (final update in updates) {
          final stockRef = _firestore
              .collection('pharmacies/$pharmacieId/medicaments')
              .doc(update['id'] as String);
          final stock = await transaction.get(stockRef);
          if (!stock.exists || stock.data()?['est_actif'] == false) {
            throw StateError('Produit supprimé sur un autre appareil.');
          }
          final current = MedicamentModel.fromMap(
            stock.data()!,
            update['id'] as String,
          );
          if (reconciliation == null) {
            _checkRevision(stock.data(), update['expected_revision'] as int);
          } else {
            final shown = reconciliation.stocks.firstWhere(
              (entry) => entry.id == current.id,
            );
            if (SyncCodec.encode(shown.toMap()) !=
                SyncCodec.encode(current.toMap())) {
              throw StateError(
                'Le stock a changé depuis la prévisualisation. Vérifiez à nouveau.',
              );
            }
          }
          final line = sale.items.singleWhere(
            (entry) => entry.medicamentId == current.id,
          );
          final original = MedicamentModel.fromMap(
            Map<String, dynamic>.from(update['document'] as Map),
            current.id,
          );
          _checkSaleStock(current, original, line, sale.date);
          documents.add(current.deduireArticle(line, sale.date).toMap());
          references.add(stockRef);
        }
        _assertSession();
        for (var index = 0; index < updates.length; index++) {
          transaction.set(references[index], {
            ...documents[index],
            '_operation_id': operationId,
          }, SetOptions(merge: true));
        }
      } else if (item['operation'] == 'set' && table != 'ventes') {
        _checkRevision(remote.data(), data['expected_revision'] as int);
        if (table == 'medicaments') {
          final incoming = MedicamentModel.fromMap(
            document,
            operation.documentId,
          )..validate();
          if (remote.data()?['suivi_lots'] == true) {
            final current = MedicamentModel.fromMap(
              remote.data()!,
              operation.documentId,
            );
            if (!incoming.suiviLots ||
                incoming.unitePrix != current.unitePrix ||
                incoming.unites.cartonsParBoite !=
                    current.unites.cartonsParBoite ||
                incoming.unites.boitesParPlaquette !=
                    current.unites.boitesParPlaquette ||
                incoming.unites.plaquettesParComprime !=
                    current.unites.plaquettesParComprime) {
              throw StateError(
                'Le suivi des lots est activé sur un autre appareil. Cette ancienne modification ne peut pas le remplacer.',
              );
            }
          }
        }
      } else {
        throw StateError('Opération de synchronisation inconnue.');
      }
      _assertSession();
      transaction.set(reference, {
        ...document,
        '_operation_id': operationId,
      }, SetOptions(merge: true));
      transaction.set(receiptRef, {
        'pharmacie_id': pharmacieId,
        'type': 'synchronisation',
        'operation_id': operationId,
        'collection': collection,
        'doc_id': operation.documentId,
        'fingerprint': operation.fingerprint,
        'date': FieldValue.serverTimestamp(),
        'rapprochee': reconciliation != null,
      });
      for (final activity in operation.activities) {
        transaction.set(
          _firestore.doc('pharmacies/$pharmacieId/activites/${activity['id']}'),
          Map<String, dynamic>.from(activity['document'] as Map),
        );
      }
    });
  }

  void _checkSaleStock(
    MedicamentModel current,
    MedicamentModel original,
    VenteItemModel line,
    DateTime saleDate,
  ) {
    current.validate();
    if (!current.estActif ||
        current.pharmacieId != pharmacieId ||
        current.suiviLots != original.suiviLots ||
        current.unitePrix != original.unitePrix ||
        current.unites.cartonsParBoite != original.unites.cartonsParBoite ||
        current.unites.boitesParPlaquette !=
            original.unites.boitesParPlaquette ||
        current.unites.plaquettesParComprime !=
            original.unites.plaquettesParComprime) {
      throw StateError(
        'Le conditionnement de ${current.nom} a changé ou le produit est archivé. Contactez le support.',
      );
    }
    current.deduireArticle(line, saleDate);
    if (line.quantite <= 0 ||
        line.quantite > current.unites.disponible(line.unite)) {
      throw StateError(
        '${current.nom} : ${line.quantite} ${line.unite} vendus, '
        '${current.unites.disponible(line.unite)} disponibles sur le serveur. '
        'Vérifiez le stock physique. La vente reste conservée sur cet appareil.',
      );
    }
  }

  Future<List<SyncOperation>> pendingOperations() async {
    _assertSession();
    final db = await _database();
    final rows = await LocalDatabase.getPendingSync(pharmacieId!, executor: db);
    _assertSession();
    return rows.map(SyncOperation.new).toList();
  }

  Future<SaleReconciliation> previewSaleReconciliation(int id) async {
    _assertSession();
    if (_inFlight != null) {
      throw StateError('Attendez la fin de la synchronisation.');
    }
    if (!await _isConnected()) {
      throw StateError('Une connexion Internet est nécessaire.');
    }
    final pending = await pendingOperations();
    final matches = pending.where((entry) => entry.id == id);
    if (matches.isEmpty) {
      throw StateError('Cette opération a déjà été traitée.');
    }
    final operation = matches.single..validate(pharmacieId!);
    if (operation.kind != 'sale') {
      throw StateError('Seules les ventes peuvent être rapprochées ici.');
    }
    if (pending.any(
      (entry) => entry.id < id && entry.overlaps(operation.affected),
    )) {
      throw StateError(
        'Traitez d’abord la première opération concernant ces produits.',
      );
    }
    if (pending.any(
      (entry) =>
          entry.id > id &&
          entry.kind != 'sale' &&
          entry.overlaps(operation.affected),
    )) {
      throw StateError(
        'Ces produits ont aussi été modifiés après la vente. Créez une sauvegarde et contactez le support pour rapprocher l’ensemble sans perte.',
      );
    }
    final remoteSale = await _firestore
        .doc('${operation.collection}/${operation.documentId}')
        .get(const GetOptions(source: Source.server));
    _assertSession();
    if (remoteSale.exists) {
      if (remoteSale.data()?['_operation_id'] != operation.operationId) {
        throw StateError(
          'Une autre vente porte ce numéro. Contactez le support.',
        );
      }
      return SaleReconciliation(operation, [], alreadySent: true);
    }
    final sale = VenteModel.fromMap(operation.document, operation.documentId);
    final stocks = <MedicamentModel>[];
    for (final update in operation.stockUpdates) {
      final remote = await _firestore
          .doc('pharmacies/$pharmacieId/medicaments/${update['id']}')
          .get(const GetOptions(source: Source.server));
      _assertSession();
      if (!remote.exists) {
        throw StateError(
          'Un produit est absent du serveur. Contactez le support.',
        );
      }
      final current = MedicamentModel.fromMap(remote.data()!, remote.id);
      _checkSaleStock(
        current,
        MedicamentModel.fromMap(
          Map<String, dynamic>.from(update['document'] as Map),
          remote.id,
        ),
        sale.items.singleWhere((entry) => entry.medicamentId == remote.id),
        sale.date,
      );
      stocks.add(current);
    }
    return SaleReconciliation(operation, stocks);
  }

  Future<void> reconcileSale(SaleReconciliation preview) async {
    if (_inFlight != null) {
      throw StateError('Attendez la fin de la synchronisation.');
    }
    _assertSession();
    await _exclusive(() async {
      _emit(const SyncStatus(running: true));
      try {
        final db = await _database();
        final operation = await db.transaction((transaction) async {
          _assertSession();
          final pending = (await LocalDatabase.getPendingSync(
            pharmacieId!,
            executor: transaction,
          )).map(SyncOperation.new).toList();
          final operation = pending.firstWhere(
            (entry) => entry.id == preview.operation.id,
          );
          if (operation.operationId != preview.operation.operationId ||
              operation.fingerprint != preview.operation.fingerprint ||
              operation.owner != pharmacieId ||
              pending.any(
                (entry) =>
                    entry.id != operation.id &&
                    entry.overlaps(operation.affected) &&
                    (entry.id < operation.id || entry.kind != 'sale'),
              )) {
            throw StateError('Les opérations ont changé. Rechargez le suivi.');
          }
          await transaction.update(
            'sync_queue',
            {
              'last_error':
                  'Rapprochement en cours. Vérifiez cette vente avant de modifier ces produits.',
            },
            where: 'id = ? AND pharmacie_id = ?',
            whereArgs: [operation.id, pharmacieId],
          );
          return operation;
        });
        await _push(operation.row, reconciliation: preview);
        _assertSession();
        await _acknowledge(db, operation.row);
        await _pull(db);
        _emit(const SyncStatus());
      } catch (error) {
        _emit(SyncStatus(error: userMessage(error)));
        rethrow;
      } finally {
        LocalDatabase.notifyChanged();
      }
    });
  }

  Future<void> maintenance(Future<void> Function() action) async {
    if (_inFlight != null) {
      throw StateError('Attendez la fin de la synchronisation puis réessayez.');
    }
    _assertSession();
    await _exclusive(action);
  }

  void _checkRevision(Map<String, dynamic>? remote, int expected) {
    final actual = (remote?['revision'] as num?)?.toInt() ?? 0;
    if (actual != expected || (remote == null && expected != 0)) {
      throw StateError(
        'Conflit entre appareils. Les modifications locales sont conservées. '
        'Exportez une sauvegarde et rapprochez les stocks avant de poursuivre.',
      );
    }
  }

  Future<void> _acknowledge(Database db, Map<String, dynamic> item) async {
    final data = SyncCodec.decode(item['data'] as String);
    await db.transaction((transaction) async {
      _assertSession();
      final remaining = (await LocalDatabase.getPendingSync(
        pharmacieId!,
        executor: transaction,
      )).where((entry) => entry['id'] != item['id']).map(SyncOperation.new);
      final protected = remaining.expand((entry) => entry.affected).toSet();
      final table = (item['collection'] as String).split('/').last;
      if (table == 'ventes') {
        await transaction.update(
          'ventes',
          {'synced': 1},
          where: 'id = ? AND pharmacie_id = ?',
          whereArgs: [item['doc_id'], pharmacieId],
        );
        for (final update in data['stock_updates'] as List) {
          if (protected.contains('*') ||
              protected.contains('medicaments/${update['id']}')) {
            continue;
          }
          await transaction.update(
            'medicaments',
            {'synced': 1},
            where: 'id = ? AND pharmacie_id = ?',
            whereArgs: [update['id'], pharmacieId],
          );
        }
      } else {
        if (!protected.contains('*') &&
            !protected.contains('$table/${item['doc_id']}')) {
          await transaction.update(
            table,
            {'synced': 1},
            where: 'id = ? AND pharmacie_id = ?',
            whereArgs: [item['doc_id'], pharmacieId],
          );
        }
      }
      for (final activity in SyncOperation(item).activities) {
        await transaction.update(
          'activites',
          {'synced': 1},
          where: 'id = ? AND pharmacie_id = ?',
          whereArgs: [activity['id'], pharmacieId],
        );
      }
      await transaction.delete(
        'sync_queue',
        where: 'id = ? AND pharmacie_id = ?',
        whereArgs: [item['id'], pharmacieId],
      );
    });
  }

  Future<void> _pull(Database db) async {
    for (final table in [
      'medicaments',
      'fournisseurs',
      'ventes',
      'activites',
    ]) {
      _assertSession();
      Query<Map<String, dynamic>> query = _firestore.collection(
        'pharmacies/$pharmacieId/$table',
      );
      if (table == 'activites') {
        query = query.where('type', isEqualTo: 'mouvement_stock');
      }
      final snapshot = await query.get(const GetOptions(source: Source.server));
      _assertSession();
      await db.transaction((transaction) async {
        _assertSession();
        final protected = (await LocalDatabase.getPendingSync(
          pharmacieId!,
          executor: transaction,
        )).map(SyncOperation.new).expand((entry) => entry.affected).toSet();
        for (final doc in snapshot.docs) {
          if (protected.contains('*') ||
              protected.contains('$table/${doc.id}')) {
            continue;
          }
          final rows = await transaction.query(
            table,
            where: 'id = ? AND pharmacie_id = ?',
            whereArgs: [doc.id, pharmacieId],
          );
          if (rows.isNotEmpty && rows.first['synced'] == 0) continue;
          final data = {...doc.data(), 'pharmacie_id': pharmacieId};
          Map<String, dynamic> local;
          if (table == 'medicaments') {
            final med = MedicamentModel.fromMap(data, doc.id);
            if (med.suiviLots) med.validate();
            if (med.nom.trim().isEmpty) {
              throw StateError('Médicament cloud incomplet : ${doc.id}.');
            }
            local = med.toSql(synced: true);
          } else if (table == 'fournisseurs') {
            final supplier = FournisseurModel.fromMap(data, doc.id);
            if (supplier.nom.trim().isEmpty) {
              throw StateError('Fournisseur cloud incomplet : ${doc.id}.');
            }
            local = supplier.toSql(synced: true);
          } else if (table == 'activites') {
            local = ActiviteModel.fromMap(data, doc.id).toSql(synced: true);
          } else {
            local = VenteModel.fromMap(data, doc.id).toSql(synced: true);
          }
          if (rows.isEmpty) {
            await transaction.insert(table, local);
          } else {
            await transaction.update(
              table,
              local,
              where: 'id = ? AND pharmacie_id = ?',
              whereArgs: [doc.id, pharmacieId],
            );
          }
          if (table == 'ventes') {
            final vente = VenteModel.fromMap(data, doc.id);
            await transaction.delete(
              'vente_items',
              where: 'vente_id = ?',
              whereArgs: [doc.id],
            );
            for (var index = 0; index < vente.items.length; index++) {
              await transaction.insert('vente_items', {
                ...vente.items[index].toSql(),
                'id': '${doc.id}_$index',
                'vente_id': doc.id,
              });
            }
          }
        }
      });
    }
  }

  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _timer?.cancel();
    _scheduled?.cancel();
    _statusController.close();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
  final userId = ref.watch(currentUserProvider)?.uid;
  final service = SyncService(
    ref.watch(firestoreProvider),
    pharmacieId:
        pharmacie != null &&
            pharmacie.id == userId &&
            ref.watch(pharmacieAuthorizedProvider)
        ? userId
        : null,
    sessionValid: () =>
        ref.read(currentUserProvider)?.uid == userId &&
        ref.read(pharmacieAuthorizedProvider) &&
        ref.read(currentPharmacieProvider).valueOrNull?.id == userId,
    canWrite: () =>
        ref.read(pharmacieWritableProvider) &&
        ref.read(currentPharmacieProvider).valueOrNull?.id == userId,
  );
  service.init();
  ref.onDispose(service.dispose);
  return service;
});

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).statuses,
);

final connectivityProvider = StreamProvider<ConnectivityResult>((ref) async* {
  yield await Connectivity().checkConnectivity();
  yield* Connectivity().onConnectivityChanged;
});

final isOnlineProvider = Provider<bool>(
  (ref) =>
      ref.watch(connectivityProvider).valueOrNull != null &&
      ref.watch(connectivityProvider).valueOrNull != ConnectivityResult.none,
);
