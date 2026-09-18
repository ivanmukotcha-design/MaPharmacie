import 'package:cloud_firestore/cloud_firestore.dart';

class PharmacieModel {
  final String id;
  final String code;
  final String nom;
  final String username;
  final String email;
  final String telephone;
  final String adresse;
  final String ville;
  final String pays;
  final String proprietaireNom;
  final DateTime createdAt;
  final bool tarifsGrosActifs;

  const PharmacieModel({
    required this.id,
    required this.code,
    required this.nom,
    required this.username,
    required this.email,
    required this.telephone,
    required this.adresse,
    required this.ville,
    required this.pays,
    required this.proprietaireNom,
    required this.createdAt,
    this.tarifsGrosActifs = false,
  });

  factory PharmacieModel.fromMap(Map<String, dynamic> map, String id) =>
      PharmacieModel(
        id: id,
        code: map['code'] ?? '',
        nom: map['nom'] ?? '',
        username: map['username'] ?? '',
        email: map['email'] ?? '',
        telephone: map['telephone'] ?? '',
        adresse: map['adresse'] ?? '',
        ville: map['ville'] ?? '',
        pays: map['pays'] ?? '',
        proprietaireNom: map['proprietaire_nom'] ?? '',
        createdAt:
            (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
        tarifsGrosActifs: map['tarifs_gros_actifs'] == true,
      );

  Map<String, dynamic> toMap() => {
    'code': code,
    'nom': nom,
    'username': username,
    'email': email,
    'telephone': telephone,
    'adresse': adresse,
    'ville': ville,
    'pays': pays,
    'proprietaire_nom': proprietaireNom,
    'created_at': Timestamp.fromDate(createdAt),
    'tarifs_gros_actifs': tarifsGrosActifs,
  };
}

class MedicamentModel {
  final String id;
  final String pharmacieId;
  final String nom;
  final String categorie;
  final String description;
  final double? prixGrossiste;
  final double prixDetail;
  final double? prixAchat;
  final String unitePrix;
  final int revision;
  final String fournisseurId;
  final String fournisseurNom;
  final String? imageUrl;
  final DateTime? dateExpiration;
  final String? codeBarres;
  final int seuilAlerte;
  final UnitesStock unites;
  final bool estActif;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MedicamentModel({
    required this.id,
    required this.pharmacieId,
    required this.nom,
    required this.categorie,
    required this.description,
    this.prixGrossiste,
    required this.prixDetail,
    this.prixAchat,
    this.unitePrix = 'boite',
    this.revision = 0,
    required this.fournisseurId,
    required this.fournisseurNom,
    required this.seuilAlerte,
    required this.unites,
    required this.estActif,
    required this.createdAt,
    required this.updatedAt,
    this.imageUrl,
    this.dateExpiration,
    this.codeBarres,
  });

  factory MedicamentModel.fromMap(Map<String, dynamic> map, String id) {
    final units = UnitesStock.fromMap(
      Map<String, dynamic>.from(map['unites'] as Map? ?? {}),
    );
    return MedicamentModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      nom: map['nom'] ?? '',
      categorie: map['categorie'] ?? '',
      description: map['description'] ?? '',
      prixGrossiste: (map['prix_grossiste'] as num?)?.toDouble(),
      prixDetail: (map['prix_detail'] ?? 0).toDouble(),
      prixAchat: (map['prix_achat'] as num?)?.toDouble(),
      unitePrix:
          map['unite_prix'] ??
          (units.flacons > 0 && units.totalComprimes == 0 ? 'flacon' : 'boite'),
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      fournisseurId: map['fournisseur_id'] ?? '',
      fournisseurNom: map['fournisseur_nom'] ?? '',
      imageUrl: map['image_url'],
      dateExpiration: (map['date_expiration'] as Timestamp?)?.toDate(),
      codeBarres: map['code_barres'],
      seuilAlerte: map['seuil_alerte'] ?? 10,
      unites: UnitesStock.fromMap(map['unites'] ?? {}),
      estActif: map['est_actif'] ?? true,
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'pharmacie_id': pharmacieId,
    'nom': nom,
    'categorie': categorie,
    'description': description,
    'prix_grossiste': prixGrossiste,
    'prix_detail': prixDetail,
    'prix_achat': prixAchat,
    'unite_prix': unitePrix,
    'revision': revision,
    'fournisseur_id': fournisseurId,
    'fournisseur_nom': fournisseurNom,
    'image_url': imageUrl,
    'date_expiration': dateExpiration != null
        ? Timestamp.fromDate(dateExpiration!)
        : null,
    'code_barres': codeBarres,
    'seuil_alerte': seuilAlerte,
    'unites': unites.toMap(),
    'est_actif': estActif,
    'created_at': Timestamp.fromDate(createdAt),
    'updated_at': Timestamp.fromDate(updatedAt),
  };

  factory MedicamentModel.fromSql(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row);
    for (final key in ['created_at', 'updated_at', 'date_expiration']) {
      final value = data[key] as String?;
      data[key] = value == null
          ? null
          : Timestamp.fromDate(DateTime.parse(value));
    }
    data['est_actif'] = row['est_actif'] == 1;
    data['unites'] = UnitesStock.fromMap(row).toMap();
    return MedicamentModel.fromMap(data, row['id'] as String);
  }

  Map<String, dynamic> toSql({bool synced = false}) {
    final data = toMap()..remove('unites');
    return {
      ...data,
      ...unites.toMap(),
      'id': id,
      'date_expiration': dateExpiration?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'est_actif': estActif ? 1 : 0,
      'synced': synced ? 1 : 0,
    };
  }

  MedicamentModel copyWith({
    UnitesStock? unites,
    bool? estActif,
    int? revision,
  }) {
    return MedicamentModel.fromMap({
      ...toMap(),
      'unites': (unites ?? this.unites).toMap(),
      'est_actif': estActif ?? this.estActif,
      'revision': revision ?? this.revision,
      'updated_at': Timestamp.now(),
    }, id);
  }

  void validate() {
    if (nom.trim().isEmpty || pharmacieId.isEmpty || id.isEmpty) {
      throw const FormatException('Le nom et la pharmacie sont requis.');
    }
    for (final price in [
      if (prixGrossiste != null) prixGrossiste!,
      prixDetail,
      if (prixAchat != null) prixAchat!,
    ]) {
      if (!price.isFinite || price < 0) {
        throw const FormatException(
          'Les prix doivent être des nombres positifs ou nuls.',
        );
      }
    }
    if (seuilAlerte < 0)
      throw const FormatException('Seuil de stock invalide.');
    unites.validate();
    unites.facteur(unitePrix);
    if (unites.flacons > 0 && unitePrix != 'flacon') {
      throw const FormatException('Choisissez le flacon comme unité tarifée.');
    }
    if (unitePrix == 'flacon' && unites.totalComprimes > 0) {
      throw const FormatException(
        'Les flacons et comprimés doivent avoir des fiches distinctes.',
      );
    }
  }

  double prixPourUnite(String unite, {required bool gros}) {
    final price = gros ? prixGrossiste : prixDetail;
    if (price == null)
      throw StateError('Aucun tarif de gros renseigné pour $nom.');
    return _convertirPrix(price, unite);
  }

  double coutPourUnite(String unite) {
    if (prixAchat == null) {
      throw StateError('Renseignez le prix d’achat de $nom avant de vendre.');
    }
    return _convertirPrix(prixAchat!, unite);
  }

  double _convertirPrix(double prix, String unite) {
    if ((unite == 'flacon') != (unitePrix == 'flacon')) {
      throw const FormatException(
        'Conditionnement incompatible avec ce produit.',
      );
    }
    return prix * unites.facteur(unite) / unites.facteur(unitePrix);
  }

  // Stock total en unité de base (comprimés/flacons)
  int get stockTotal => unites.totalUniteBase;

  bool get estEnRupture => stockTotal == 0;
  bool get estStockFaible =>
      stockTotal > 0 &&
      (unitePrix == 'flacon' ? unites.flacons : unites.totalBoites) <=
          seuilAlerte;

  bool get estExpire {
    if (dateExpiration == null) return false;
    return DateTime.now().isAfter(dateExpiration!);
  }

  bool get expireBientot {
    if (dateExpiration == null) return false;
    final diff = dateExpiration!.difference(DateTime.now());
    return !estExpire && diff <= const Duration(days: 30);
  }

  StatutStock get statutStock {
    if (estEnRupture) return StatutStock.rupture;
    if (estStockFaible) return StatutStock.faible;
    return StatutStock.correct;
  }
}

enum StatutStock { correct, faible, rupture }

// ─── UNITÉS DE STOCK ─────────────────────────────────────────────────────────

class UnitesStock {
  final int cartons;
  final int boites;
  final int plaquettes;
  final int comprimes;
  final int flacons;

  // Ratios de conversion
  final int cartonsParBoite; // ex: 1 carton = 20 boites
  final int boitesParPlaquette; // ex: 1 boite = 10 plaquettes
  final int plaquettesParComprime; // ex: 1 plaquette = 10 comprimes

  const UnitesStock({
    this.cartons = 0,
    this.boites = 0,
    this.plaquettes = 0,
    this.comprimes = 0,
    this.flacons = 0,
    this.cartonsParBoite = 20,
    this.boitesParPlaquette = 10,
    this.plaquettesParComprime = 10,
  });

  factory UnitesStock.fromMap(Map<String, dynamic> map) {
    return UnitesStock(
      cartons: map['cartons'] ?? 0,
      boites: map['boites'] ?? 0,
      plaquettes: map['plaquettes'] ?? 0,
      comprimes: map['comprimes'] ?? 0,
      flacons: map['flacons'] ?? 0,
      cartonsParBoite: map['cartons_par_boite'] ?? 20,
      boitesParPlaquette: map['boites_par_plaquette'] ?? 10,
      plaquettesParComprime: map['plaquettes_par_comprime'] ?? 10,
    );
  }

  Map<String, dynamic> toMap() => {
    'cartons': cartons,
    'boites': boites,
    'plaquettes': plaquettes,
    'comprimes': comprimes,
    'flacons': flacons,
    'cartons_par_boite': cartonsParBoite,
    'boites_par_plaquette': boitesParPlaquette,
    'plaquettes_par_comprime': plaquettesParComprime,
  };

  // Total des boites (pour comparaison avec seuil)
  int get totalBoites {
    return cartons * cartonsParBoite + boites;
  }

  // Total en unité de base (comprimés)
  int get totalUniteBase {
    return totalComprimes + flacons;
  }

  int get totalComprimes {
    return (cartons *
            cartonsParBoite *
            boitesParPlaquette *
            plaquettesParComprime) +
        (boites * boitesParPlaquette * plaquettesParComprime) +
        (plaquettes * plaquettesParComprime) +
        comprimes;
  }

  // Déduire une quantité vendue (en comprimés/unité base)
  UnitesStock deduire(int quantiteVendue, String unite) {
    validate();
    if (quantiteVendue <= 0) throw const FormatException('Quantité invalide.');
    final quantiteBase = quantiteVendue * facteur(unite);
    final disponible = unite == 'flacon' ? flacons : totalComprimes;
    if (quantiteBase > disponible) throw StateError('Stock insuffisant.');
    if (unite == 'flacon') {
      return UnitesStock.fromMap({
        ...toMap(),
        'flacons': flacons - quantiteVendue,
      });
    }
    return _reconstruireDepuisBase(totalComprimes - quantiteBase);
  }

  void validate() {
    if ([
      cartons,
      boites,
      plaquettes,
      comprimes,
      flacons,
    ].any((value) => value < 0)) {
      throw const FormatException(
        'Les quantités ne peuvent pas être négatives.',
      );
    }
    if ([
      cartonsParBoite,
      boitesParPlaquette,
      plaquettesParComprime,
    ].any((value) => value <= 0)) {
      throw const FormatException('Les ratios doivent être supérieurs à zéro.');
    }
    if (flacons > 0 && totalComprimes > 0) {
      throw const FormatException('Séparez les flacons et les comprimés.');
    }
  }

  int disponible(String unite) {
    validate();
    return (unite == 'flacon' ? flacons : totalComprimes) ~/ facteur(unite);
  }

  int facteur(String unite) {
    switch (unite) {
      case 'carton':
        return cartonsParBoite * boitesParPlaquette * plaquettesParComprime;
      case 'boite':
        return boitesParPlaquette * plaquettesParComprime;
      case 'plaquette':
        return plaquettesParComprime;
      case 'comprimes':
        return 1;
      case 'flacon':
        return 1;
      default:
        throw const FormatException('Unité inconnue.');
    }
  }

  UnitesStock _reconstruireDepuisBase(int totalBase) {
    int restant = totalBase;
    final perCarton =
        cartonsParBoite * boitesParPlaquette * plaquettesParComprime;
    final perBoite = boitesParPlaquette * plaquettesParComprime;
    final perPlaquette = plaquettesParComprime;

    final newCartons = restant ~/ perCarton;
    restant %= perCarton;
    final newBoites = restant ~/ perBoite;
    restant %= perBoite;
    final newPlaquettes = restant ~/ perPlaquette;
    restant %= perPlaquette;

    return UnitesStock(
      cartons: newCartons,
      boites: newBoites,
      plaquettes: newPlaquettes,
      comprimes: restant,
      flacons: flacons,
      cartonsParBoite: cartonsParBoite,
      boitesParPlaquette: boitesParPlaquette,
      plaquettesParComprime: plaquettesParComprime,
    );
  }

  String get affichage {
    final parts = <String>[];
    if (cartons > 0) parts.add('$cartons carton${cartons > 1 ? 's' : ''}');
    if (boites > 0) parts.add('$boites boîte${boites > 1 ? 's' : ''}');
    if (plaquettes > 0)
      parts.add('$plaquettes plaquette${plaquettes > 1 ? 's' : ''}');
    if (comprimes > 0)
      parts.add('$comprimes comprimé${comprimes > 1 ? 's' : ''}');
    if (flacons > 0) parts.add('$flacons flacon${flacons > 1 ? 's' : ''}');
    return parts.isEmpty ? '0' : parts.join(' + ');
  }
}

// ─── FOURNISSEUR ──────────────────────────────────────────────────────────────

class FournisseurModel {
  final String id;
  final String pharmacieId;
  final String nom;
  final String telephone;
  final String email;
  final String adresse;
  final String? notes;
  final DateTime createdAt;
  final bool estActif;
  final int revision;

  const FournisseurModel({
    required this.id,
    required this.pharmacieId,
    required this.nom,
    required this.telephone,
    required this.email,
    required this.adresse,
    required this.createdAt,
    this.notes,
    this.estActif = true,
    this.revision = 0,
  });

  factory FournisseurModel.fromMap(Map<String, dynamic> map, String id) {
    return FournisseurModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      nom: map['nom'] ?? '',
      telephone: map['telephone'] ?? '',
      email: map['email'] ?? '',
      adresse: map['adresse'] ?? '',
      notes: map['notes'],
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      estActif: map['est_actif'] ?? true,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'pharmacie_id': pharmacieId,
    'nom': nom,
    'telephone': telephone,
    'email': email,
    'adresse': adresse,
    'notes': notes,
    'created_at': Timestamp.fromDate(createdAt),
    'est_actif': estActif,
    'revision': revision,
  };

  factory FournisseurModel.fromSql(Map<String, dynamic> row) {
    return FournisseurModel.fromMap({
      ...row,
      'est_actif': row['est_actif'] == 1,
      'created_at': row['created_at'] == null
          ? null
          : Timestamp.fromDate(DateTime.parse(row['created_at'] as String)),
    }, row['id'] as String);
  }

  Map<String, dynamic> toSql({bool synced = false}) => {
    ...toMap(),
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'est_actif': estActif ? 1 : 0,
    'synced': synced ? 1 : 0,
  };
}

// ─── VENTE ────────────────────────────────────────────────────────────────────

class VenteModel {
  final String id;
  final String pharmacieId;
  final String typeVente; // detail | gros
  final List<VenteItemModel> items;
  final double totalHT;
  final double totalTTC;
  final double benefice;
  final DateTime date;
  final String? notes;

  const VenteModel({
    required this.id,
    required this.pharmacieId,
    required this.typeVente,
    required this.items,
    required this.totalHT,
    required this.totalTTC,
    required this.benefice,
    required this.date,
    this.notes,
  });

  factory VenteModel.fromMap(Map<String, dynamic> map, String id) {
    final itemsList = (map['items'] as List<dynamic>? ?? [])
        .map((item) => VenteItemModel.fromMap(item as Map<String, dynamic>))
        .toList();
    return VenteModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      typeVente: map['type_vente'] ?? 'detail',
      items: itemsList,
      totalHT: (map['total_ht'] ?? 0).toDouble(),
      totalTTC: (map['total_ttc'] ?? 0).toDouble(),
      benefice: (map['benefice'] ?? 0).toDouble(),
      date: (map['date'] as Timestamp).toDate(),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() => {
    'pharmacie_id': pharmacieId,
    'type_vente': typeVente,
    'items': items.map((i) => i.toMap()).toList(),
    'total_ht': totalHT,
    'total_ttc': totalTTC,
    'benefice': benefice,
    'date': Timestamp.fromDate(date),
    'notes': notes,
  };

  factory VenteModel.fromSql(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> items,
  ) {
    return VenteModel.fromMap({
      ...row,
      'items': items,
      'date': Timestamp.fromDate(DateTime.parse(row['date'] as String)),
    }, row['id'] as String);
  }

  Map<String, dynamic> toSql({bool synced = false}) {
    final data = toMap()..remove('items');
    return {
      ...data,
      'id': id,
      'date': date.toIso8601String(),
      'synced': synced ? 1 : 0,
    };
  }
}

class VenteItemModel {
  final String medicamentId;
  final String medicamentNom;
  final int quantite;
  final String unite;
  final double prixUnitaire;
  final double prixAchat;
  final double sousTotal;

  const VenteItemModel({
    required this.medicamentId,
    required this.medicamentNom,
    required this.quantite,
    required this.unite,
    required this.prixUnitaire,
    required this.prixAchat,
    required this.sousTotal,
  });

  factory VenteItemModel.fromMap(Map<String, dynamic> map) {
    return VenteItemModel(
      medicamentId: map['medicament_id'] ?? '',
      medicamentNom: map['medicament_nom'] ?? '',
      quantite: map['quantite'] ?? 0,
      unite: map['unite'] ?? 'comprimes',
      prixUnitaire: (map['prix_unitaire'] ?? 0).toDouble(),
      prixAchat: (map['prix_achat'] ?? 0).toDouble(),
      sousTotal: (map['sous_total'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'medicament_id': medicamentId,
    'medicament_nom': medicamentNom,
    'quantite': quantite,
    'unite': unite,
    'prix_unitaire': prixUnitaire,
    'prix_achat': prixAchat,
    'sous_total': sousTotal,
  };

  double get beneficeItem => sousTotal - (prixAchat * quantite);
}

// ─── ACTIVITÉ ─────────────────────────────────────────────────────────────────

class ActiviteModel {
  final String id;
  final String pharmacieId;
  final String type;
  final String description;
  final Map<String, dynamic>? metadata;
  final DateTime date;

  const ActiviteModel({
    required this.id,
    required this.pharmacieId,
    required this.type,
    required this.description,
    required this.date,
    this.metadata,
  });

  factory ActiviteModel.fromMap(Map<String, dynamic> map, String id) {
    return ActiviteModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      type: map['type'] ?? '',
      description: map['description'] ?? '',
      metadata: map['metadata'] as Map<String, dynamic>?,
      date: (map['date'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'pharmacie_id': pharmacieId,
    'type': type,
    'description': description,
    'metadata': metadata,
    'date': Timestamp.fromDate(date),
  };
}

// ─── DASHBOARD STATS ─────────────────────────────────────────────────────────

class DashboardStats {
  final int totalMedicaments;
  final int stockFaible;
  final int enRupture;
  final int expires;
  final int expireBientot;
  final double ventesJour;
  final double beneficesJour;
  final int ventesCount;

  const DashboardStats({
    required this.totalMedicaments,
    required this.stockFaible,
    required this.enRupture,
    required this.expires,
    required this.expireBientot,
    required this.ventesJour,
    required this.beneficesJour,
    required this.ventesCount,
  });
}
