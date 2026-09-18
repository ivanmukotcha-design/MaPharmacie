import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../config/auth_provider.dart';
import '../local_database/local_database.dart';
import '../local_database/sync_codec.dart';
import '../models/models.dart';

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
    if (_inFlight != null) return _inFlight!;
    final completer = Completer<void>();
    _inFlight = completer.future;
    _synchronize()
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
      if (!await _isConnected())
        throw StateError('Hors ligne : données conservées sur cet appareil.');
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
      for (final item in pending) {
        _assertSession();
        try {
          await _push(item);
          _assertSession();
          await _acknowledge(db, item);
        } catch (error) {
          await db.rawUpdate(
            'UPDATE sync_queue SET attempts = attempts + 1, last_error = ? WHERE id = ? AND pharmacie_id = ?',
            [error.toString(), item['id'], pharmacieId],
          );
          rethrow;
        }
      }
      _assertSession();
      await _pull(db);
      _emit(const SyncStatus());
    } catch (error) {
      _emit(SyncStatus(error: error.toString()));
      rethrow;
    } finally {
      LocalDatabase.notifyChanged();
    }
  }

  Future<void> _push(Map<String, dynamic> item) async {
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
    if (document['pharmacie_id'] != pharmacieId)
      throw StateError('Pharmacie incohérente.');
    final operationId = item['operation_id'] as String;
    final reference = _firestore
        .collection(collection)
        .doc(item['doc_id'] as String);
    await _firestore.runTransaction((transaction) async {
      _assertSession();
      if (!_canWrite()) throw StateError('La pharmacie est en lecture seule.');
      final remote = await transaction.get(reference);
      if (remote.data()?['_operation_id'] == operationId) return;
      if (item['operation'] == 'sale') {
        if (remote.exists)
          throw StateError('Une autre vente utilise cet identifiant.');
        final updates = (data['stock_updates'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
        final references = <DocumentReference<Map<String, dynamic>>>[];
        for (final update in updates) {
          final stockRef = _firestore
              .collection('pharmacies/$pharmacieId/medicaments')
              .doc(update['id'] as String);
          final stock = await transaction.get(stockRef);
          if (!stock.exists || stock.data()?['est_actif'] == false) {
            throw StateError('Produit supprimé sur un autre appareil.');
          }
          _checkRevision(stock.data(), update['expected_revision'] as int);
          references.add(stockRef);
        }
        _assertSession();
        for (var index = 0; index < updates.length; index++) {
          transaction.set(references[index], {
            ...Map<String, dynamic>.from(updates[index]['document'] as Map),
            '_operation_id': operationId,
          }, SetOptions(merge: true));
        }
      } else if (item['operation'] == 'set' && table != 'ventes') {
        _checkRevision(remote.data(), data['expected_revision'] as int);
      } else {
        throw StateError('Opération de synchronisation inconnue.');
      }
      _assertSession();
      transaction.set(reference, {
        ...document,
        '_operation_id': operationId,
      }, SetOptions(merge: true));
    });
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
      final table = (item['collection'] as String).split('/').last;
      final document = Map<String, dynamic>.from(data['document'] as Map);
      if (table == 'ventes') {
        await transaction.update(
          'ventes',
          {'synced': 1},
          where: 'id = ? AND pharmacie_id = ?',
          whereArgs: [item['doc_id'], pharmacieId],
        );
        for (final update in data['stock_updates'] as List) {
          await transaction.update(
            'medicaments',
            {'synced': 1},
            where: 'id = ? AND pharmacie_id = ? AND revision = ?',
            whereArgs: [
              update['id'],
              pharmacieId,
              update['document']['revision'],
            ],
          );
        }
      } else {
        await transaction.update(
          table,
          {'synced': 1},
          where: 'id = ? AND pharmacie_id = ? AND revision = ?',
          whereArgs: [item['doc_id'], pharmacieId, document['revision']],
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
    for (final table in ['medicaments', 'fournisseurs', 'ventes']) {
      _assertSession();
      final snapshot = await _firestore
          .collection('pharmacies/$pharmacieId/$table')
          .get(const GetOptions(source: Source.server));
      _assertSession();
      await db.transaction((transaction) async {
        _assertSession();
        for (final doc in snapshot.docs) {
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
            if (med.nom.trim().isEmpty)
              throw StateError('Médicament cloud incomplet : ${doc.id}.');
            local = med.toSql(synced: true);
          } else if (table == 'fournisseurs') {
            final supplier = FournisseurModel.fromMap(data, doc.id);
            if (supplier.nom.trim().isEmpty)
              throw StateError('Fournisseur cloud incomplet : ${doc.id}.');
            local = supplier.toSql(synced: true);
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
                ...vente.items[index].toMap(),
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
        ref.read(pharmacieAuthorizedProvider) &&
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
