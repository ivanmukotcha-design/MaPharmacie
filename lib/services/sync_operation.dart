import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../local_database/sync_codec.dart';
import '../models/models.dart';

class SyncOperation {
  final Map<String, dynamic> row;
  final Map<String, dynamic> data;

  SyncOperation(Map<String, Object?> value)
    : row = Map<String, dynamic>.from(value),
      data = value['operation'] == 'legacy'
          ? {}
          : SyncCodec.decode(value['data'] as String);

  int get id => row['id'] as int;
  String get owner => row['pharmacie_id'] as String;
  String get operationId => row['operation_id'] as String;
  String get collection => row['collection'] as String;
  String get documentId => row['doc_id'] as String;
  String get kind => row['operation'] as String;
  String get table => collection.split('/').last;
  String get fingerprint =>
      sha256.convert(utf8.encode(row['data'] as String)).toString();
  String? get error => row['last_error'] as String?;
  Map<String, dynamic> get document =>
      Map<String, dynamic>.from(data['document'] as Map);
  List<Map<String, dynamic>> get stockUpdates =>
      (data['stock_updates'] as List? ?? [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
  List<Map<String, dynamic>> get activities =>
      (data['activities'] as List? ?? [])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();

  Set<String> get affected {
    if (kind == 'legacy') return {'*'};
    return {
      '$table/$documentId',
      for (final update in stockUpdates) 'medicaments/${update['id']}',
      for (final activity in activities) 'activites/${activity['id']}',
    };
  }

  bool overlaps(Set<String> others) =>
      others.isNotEmpty &&
      (others.contains('*') ||
          affected.contains('*') ||
          affected.intersection(others).isNotEmpty);

  void validate(String pharmacieId) {
    if (owner != pharmacieId ||
        collection != 'pharmacies/$pharmacieId/$table' ||
        !['medicaments', 'fournisseurs', 'ventes'].contains(table) ||
        operationId.isEmpty ||
        operationId.contains('/') ||
        documentId.isEmpty ||
        documentId.contains('/')) {
      throw const FormatException(
        'Opération étrangère à cette pharmacie ou invalide.',
      );
    }
    if (kind == 'legacy') return;
    if (document['pharmacie_id'] != pharmacieId ||
        !(kind == 'sale' && table == 'ventes' ||
            kind == 'set' && table != 'ventes')) {
      throw const FormatException('Contenu de synchronisation invalide.');
    }
    for (final update in stockUpdates) {
      if (update['id'] is! String ||
          (update['id'] as String).isEmpty ||
          (update['id'] as String).contains('/') ||
          update['document']['pharmacie_id'] != pharmacieId) {
        throw const FormatException('Stock étranger à cette pharmacie.');
      }
    }
    if (activities.length > 100 ||
        activities.map((entry) => entry['id']).toSet().length !=
            activities.length) {
      throw const FormatException('Mouvements en double ou trop nombreux.');
    }
    for (final entry in activities) {
      final id = entry['id'] as String;
      final activity = ActiviteModel.fromMap(
        Map<String, dynamic>.from(entry['document'] as Map),
        id,
      );
      final medicineId = activity.metadata?['medicament_id'];
      if (id.isEmpty ||
          id.contains('/') ||
          id.startsWith('sync_') ||
          activity.pharmacieId != pharmacieId ||
          activity.type != 'mouvement_stock' ||
          !affected.contains('medicaments/$medicineId')) {
        throw const FormatException('Mouvement de stock invalide.');
      }
    }
  }
}
