import 'package:uuid/uuid.dart';
import '../models/models.dart';

ActiviteModel stockMovement(
  MedicamentModel after, {
  required int before,
  required String kind,
  required String reason,
  String? lotId,
  String? saleId,
  List<LotAllocation> allocations = const [],
}) => ActiviteModel(
  id: const Uuid().v4(),
  pharmacieId: after.pharmacieId,
  type: 'mouvement_stock',
  description: '${after.nom} : $reason',
  date: DateTime.now(),
  metadata: {
    'medicament_id': after.id,
    'medicament_nom': after.nom,
    'nature': kind,
    'motif': reason,
    'avant': before,
    'apres': after.stockTotal,
    'variation': after.stockTotal - before,
    'unite': after.unitePrix == 'flacon' ? 'flacon' : 'comprimes',
    'lot_id': lotId,
    'vente_id': saleId,
    'lots': allocations.map((entry) => entry.toMap()).toList(),
  },
);

Map<String, dynamic> movementPayload(ActiviteModel movement) => {
  'id': movement.id,
  'document': movement.toMap(),
};
