class StockLot {
  final String id;
  final String numero;
  final int quantiteBase;
  final double coutBase;
  final DateTime? expiration;
  final DateTime reception;
  final String fournisseur;

  const StockLot({
    required this.id,
    required this.numero,
    required this.quantiteBase,
    required this.coutBase,
    required this.reception,
    this.expiration,
    this.fournisseur = '',
  });

  factory StockLot.fromMap(Map<String, dynamic> data) => StockLot(
    id: data['id'] as String,
    numero: data['numero'] as String,
    quantiteBase: data['quantite_base'] as int,
    coutBase: (data['cout_base'] as num).toDouble(),
    reception: DateTime.parse(data['reception'] as String),
    expiration: data['expiration'] == null
        ? null
        : DateTime.parse(data['expiration'] as String),
    fournisseur: data['fournisseur'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'numero': numero,
    'quantite_base': quantiteBase,
    'cout_base': coutBase,
    'reception': reception.toIso8601String(),
    'expiration': expiration?.toIso8601String(),
    'fournisseur': fournisseur,
  };

  StockLot withQuantity(int quantity) => StockLot(
    id: id,
    numero: numero,
    quantiteBase: quantity,
    coutBase: coutBase,
    reception: reception,
    expiration: expiration,
    fournisseur: fournisseur,
  );

  bool expiredAt(DateTime date) =>
      expiration != null &&
      !date.isBefore(
        DateTime(expiration!.year, expiration!.month, expiration!.day + 1),
      );

  void validate() {
    if (id.isEmpty ||
        id.length > 128 ||
        id.contains('/') ||
        numero.trim().isEmpty ||
        numero.length > 100 ||
        fournisseur.length > 200 ||
        quantiteBase < 0 ||
        quantiteBase > 1000000000000 ||
        !coutBase.isFinite ||
        coutBase < 0 ||
        !(coutBase * quantiteBase).isFinite) {
      throw const FormatException(
        'Lot invalide : vérifiez son numéro, sa quantité et son prix d’achat.',
      );
    }
  }
}

class LotAllocation {
  final String lotId;
  final String numero;
  final int quantiteBase;
  final double coutBase;
  const LotAllocation({
    required this.lotId,
    required this.numero,
    required this.quantiteBase,
    required this.coutBase,
  });
  factory LotAllocation.fromMap(Map<String, dynamic> data) => LotAllocation(
    lotId: data['lot_id'] as String,
    numero: data['numero'] as String,
    quantiteBase: data['quantite_base'] as int,
    coutBase: (data['cout_base'] as num).toDouble(),
  );
  Map<String, dynamic> toMap() => {
    'lot_id': lotId,
    'numero': numero,
    'quantite_base': quantiteBase,
    'cout_base': coutBase,
  };
  double get coutTotal => quantiteBase * coutBase;
  void validate() {
    if (lotId.isEmpty ||
        lotId.length > 128 ||
        lotId.contains('/') ||
        numero.trim().isEmpty ||
        numero.length > 100 ||
        quantiteBase <= 0 ||
        quantiteBase > 1000000000000 ||
        !coutBase.isFinite ||
        coutBase < 0 ||
        !coutTotal.isFinite) {
      throw const FormatException('Détail de lot vendu invalide.');
    }
  }
}

List<LotAllocation> allocateLots(
  List<StockLot> lots,
  int quantity,
  DateTime date,
) {
  if (quantity <= 0) {
    throw const FormatException('La quantité doit être positive.');
  }
  final available =
      lots.where((lot) => lot.quantiteBase > 0 && !lot.expiredAt(date)).toList()
        ..sort((first, second) {
          if (first.expiration == null && second.expiration != null) return 1;
          if (second.expiration == null && first.expiration != null) return -1;
          final expirationOrder =
              first.expiration?.compareTo(second.expiration!) ?? 0;
          if (expirationOrder != 0) return expirationOrder;
          final receptionOrder = first.reception.compareTo(second.reception);
          return receptionOrder != 0
              ? receptionOrder
              : first.id.compareTo(second.id);
        });
  var remaining = quantity;
  final allocations = <LotAllocation>[];
  for (final lot in available) {
    lot.validate();
    if (remaining == 0) break;
    final taken = remaining < lot.quantiteBase ? remaining : lot.quantiteBase;
    allocations.add(
      LotAllocation(
        lotId: lot.id,
        numero: lot.numero,
        quantiteBase: taken,
        coutBase: lot.coutBase,
      ),
    );
    remaining -= taken;
  }
  if (remaining > 0) {
    throw StateError(
      'Stock vendable insuffisant. Les lots expirés sont exclus.',
    );
  }
  return allocations;
}

List<StockLot> debitLots(
  List<StockLot> lots,
  List<LotAllocation> allocations,
  int quantity,
  DateTime date,
) {
  if (quantity <= 0 ||
      allocations.isEmpty ||
      allocations.map((entry) => entry.lotId).toSet().length !=
          allocations.length ||
      allocations.fold(0, (total, entry) => total + entry.quantiteBase) !=
          quantity) {
    throw const FormatException(
      'Les lots ne correspondent pas à la quantité vendue.',
    );
  }
  final remaining = {for (final lot in lots) lot.id: lot};
  for (final entry in allocations) {
    entry.validate();
    final lot = remaining[entry.lotId];
    if (lot == null ||
        lot.numero != entry.numero ||
        lot.coutBase != entry.coutBase ||
        lot.expiredAt(date) ||
        lot.quantiteBase < entry.quantiteBase) {
      throw StateError(
        'Le lot ${entry.numero} est indisponible ou a changé. Vérifiez cette vente sans choisir automatiquement un autre lot.',
      );
    }
    remaining[entry.lotId] = lot.withQuantity(
      lot.quantiteBase - entry.quantiteBase,
    );
  }
  return lots.map((lot) => remaining[lot.id]!).toList();
}
