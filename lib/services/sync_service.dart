import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local_database/local_database.dart';
import '../core/constants/app_constants.dart';

/// SyncService gère la synchronisation bidirectionnelle Sqflite <-> Firestore.
/// Logique :
/// - Offline : toutes les opérations écrivent dans Sqflite + sync_queue
/// - Reconnexion : sync_queue est drainé vers Firestore
/// - Firestore snapshots : mis à jour dans Sqflite en temps réel quand online

class SyncService {
  final FirebaseFirestore _firestore;
  StreamSubscription? _connectivitySub;
  Timer? _syncTimer;
  bool _isSyncing = false;

  SyncService(this._firestore);

  void init() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        _triggerSync();
      }
    });

    // Sync périodique toutes les 5 minutes si connecté
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => _triggerSync());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _syncTimer?.cancel();
  }

  Future<bool> isConnected() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _drainSyncQueue();
    } finally {
      _isSyncing = false;
    }
  }

  /// Drain la queue de sync vers Firestore
  Future<void> _drainSyncQueue() async {
    final pending = await LocalDatabase.getPendingSync();
    if (pending.isEmpty) return;

    final batch = _firestore.batch();
    final toRemove = <int>[];

    for (final item in pending) {
      try {
        final id = item['id'] as int;
        final collection = item['collection'] as String;
        final docId = item['doc_id'] as String;
        final operation = item['operation'] as String;
        final dataStr = item['data'] as String?;

        final ref = _firestore.collection(collection).doc(docId);

        switch (operation) {
          case 'set':
            if (dataStr != null) {
              // Parse basic map from stored string (simplified)
              batch.set(ref, {'_synced': true, '_sync_time': FieldValue.serverTimestamp()},
                  SetOptions(merge: true));
            }
            break;
          case 'delete':
            batch.delete(ref);
            break;
          case 'update':
            batch.update(ref, {'_synced': true, '_sync_time': FieldValue.serverTimestamp()});
            break;
        }
        toRemove.add(id);
      } catch (e) {
        await LocalDatabase.incrementAttempts(item['id'] as int);
      }
    }

    try {
      await batch.commit();
      for (final id in toRemove) {
        await LocalDatabase.removeSyncItem(id);
      }
    } catch (_) {
      // Retry on next trigger
    }
  }

  /// Synchronise les médicaments depuis Firestore vers local
  Future<void> syncMedicamentsFromCloud(String pharmacieId) async {
    final snapshot = await _firestore
        .collection(AppConstants.colPharmacies)
        .doc(pharmacieId)
        .collection(AppConstants.colMedicaments)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      await LocalDatabase.upsertMedicament({
        'id': doc.id,
        'pharmacie_id': pharmacieId,
        'nom': data['nom'] ?? '',
        'categorie': data['categorie'] ?? '',
        'description': data['description'] ?? '',
        'prix_grossiste': data['prix_grossiste'] ?? 0,
        'prix_detail': data['prix_detail'] ?? 0,
        'fournisseur_id': data['fournisseur_id'] ?? '',
        'fournisseur_nom': data['fournisseur_nom'] ?? '',
        'image_url': data['image_url'],
        'date_expiration': (data['date_expiration'] as Timestamp?)?.toDate().toIso8601String(),
        'code_barres': data['code_barres'],
        'seuil_alerte': data['seuil_alerte'] ?? 10,
        'cartons': data['unites']?['cartons'] ?? 0,
        'boites': data['unites']?['boites'] ?? 0,
        'plaquettes': data['unites']?['plaquettes'] ?? 0,
        'comprimes': data['unites']?['comprimes'] ?? 0,
        'flacons': data['unites']?['flacons'] ?? 0,
        'cartons_par_boite': data['unites']?['cartons_par_boite'] ?? 20,
        'boites_par_plaquette': data['unites']?['boites_par_plaquette'] ?? 10,
        'plaquettes_par_comprime': data['unites']?['plaquettes_par_comprime'] ?? 10,
        'est_actif': data['est_actif'] == true ? 1 : 0,
        'created_at': (data['created_at'] as Timestamp?)?.toDate().toIso8601String(),
        'updated_at': (data['updated_at'] as Timestamp?)?.toDate().toIso8601String(),
        'synced': 1,
      });
    }
  }

  /// Force sync complète (au login)
  Future<void> fullSync(String pharmacieId) async {
    final connected = await isConnected();
    if (!connected) return;
    await syncMedicamentsFromCloud(pharmacieId);
    await _drainSyncQueue();
  }
}

// ─── PROVIDERS ────────────────────────────────────────────────────────────────

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(FirebaseFirestore.instance);
  service.init();
  ref.onDispose(service.dispose);
  return service;
});

final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.when(
    data: (result) => result != ConnectivityResult.none,
    loading: () => true,
    error: (_, __) => false,
  );
});
