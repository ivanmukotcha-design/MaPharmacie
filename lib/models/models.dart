import 'package:cloud_firestore/cloud_firestore.dart';

// ─── PHARMACIE ────────────────────────────────────────────────────────────────

class PharmacieModel {
  final String id;
  final String code;          // PHR-0001
  final String nom;
  final String username;
  final String email;
  final String telephone;
  final String adresse;
  final String ville;
  final String pays;
  final String typePharmacie; // detaillant | grossiste
  final String statut;        // actif | expire | suspendu | attente_paiement
  final String proprietaireNom;
  final DateTime createdAt;
  final DateTime? suspendedAt;
  final String? suspendedReason;

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
    required this.typePharmacie,
    required this.statut,
    required this.proprietaireNom,
    required this.createdAt,
    this.suspendedAt,
    this.suspendedReason,
  });

  factory PharmacieModel.fromMap(Map<String, dynamic> map, String id) {
    return PharmacieModel(
      id: id,
      code: map['code'] ?? '',
      nom: map['nom'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      telephone: map['telephone'] ?? '',
      adresse: map['adresse'] ?? '',
      ville: map['ville'] ?? '',
      pays: map['pays'] ?? '',
      typePharmacie: map['type_pharmacie'] ?? 'detaillant',
      statut: map['statut'] ?? 'attente_paiement',
      proprietaireNom: map['proprietaire_nom'] ?? '',
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      suspendedAt: (map['suspended_at'] as Timestamp?)?.toDate(),
      suspendedReason: map['suspended_reason'],
    );
  }

  Map<String, dynamic> toMap() => {
    'code': code,
    'nom': nom,
    'username': username,
    'email': email,
    'telephone': telephone,
    'adresse': adresse,
    'ville': ville,
    'pays': pays,
    'type_pharmacie': typePharmacie,
    'statut': statut,
    'proprietaire_nom': proprietaireNom,
    'created_at': Timestamp.fromDate(createdAt),
    'suspended_at': suspendedAt != null ? Timestamp.fromDate(suspendedAt!) : null,
    'suspended_reason': suspendedReason,
  };

  bool get isActif => statut == 'actif';
  bool get isExpire => statut == 'expire';
  bool get isSuspendu => statut == 'suspendu';
}

// ─── ABONNEMENT ───────────────────────────────────────────────────────────────

class AbonnementModel {
  final String id;
  final String pharmacieId;
  final DateTime dateDebut;
  final DateTime dateFin;
  final double montantTotal;
  final double montantPaye;
  final String statut;
  final bool estActif;

  const AbonnementModel({
    required this.id,
    required this.pharmacieId,
    required this.dateDebut,
    required this.dateFin,
    required this.montantTotal,
    required this.montantPaye,
    required this.statut,
    required this.estActif,
  });

  factory AbonnementModel.fromMap(Map<String, dynamic> map, String id) {
    return AbonnementModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      dateDebut: (map['date_debut'] as Timestamp).toDate(),
      dateFin: (map['date_fin'] as Timestamp).toDate(),
      montantTotal: (map['montant_total'] ?? 0).toDouble(),
      montantPaye: (map['montant_paye'] ?? 0).toDouble(),
      statut: map['statut'] ?? 'en_attente',
      estActif: map['est_actif'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'pharmacie_id': pharmacieId,
    'date_debut': Timestamp.fromDate(dateDebut),
    'date_fin': Timestamp.fromDate(dateFin),
    'montant_total': montantTotal,
    'montant_paye': montantPaye,
    'statut': statut,
    'est_actif': estActif,
  };

  int get joursRestants => dateFin.difference(DateTime.now()).inDays;
  double get montantRestant => montantTotal - montantPaye;
  bool get estExpire => DateTime.now().isAfter(dateFin);
  bool get prochainExpiration => joursRestants <= 10 && joursRestants >= 0;
}

// ─── PAIEMENT ─────────────────────────────────────────────────────────────────

class PaiementModel {
  final String id;
  final String pharmacieId;
  final String abonnementId;
  final double montant;
  final String typePaiement;   // airtel_money | m_pesa
  final String statutPaiement; // complet | partiel | en_attente
  final String? reference;
  final String? notes;
  final DateTime date;
  final bool validePar;        // admin validation
  final String typePaiementAbonnement; // inscription | renouvellement | partiel

  const PaiementModel({
    required this.id,
    required this.pharmacieId,
    required this.abonnementId,
    required this.montant,
    required this.typePaiement,
    required this.statutPaiement,
    required this.date,
    required this.validePar,
    required this.typePaiementAbonnement,
    this.reference,
    this.notes,
  });

  factory PaiementModel.fromMap(Map<String, dynamic> map, String id) {
    return PaiementModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      abonnementId: map['abonnement_id'] ?? '',
      montant: (map['montant'] ?? 0).toDouble(),
      typePaiement: map['type_paiement'] ?? '',
      statutPaiement: map['statut_paiement'] ?? 'en_attente',
      date: (map['date'] as Timestamp).toDate(),
      validePar: map['valide_par'] ?? false,
      typePaiementAbonnement: map['type_paiement_abonnement'] ?? 'renouvellement',
      reference: map['reference'],
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() => {
    'pharmacie_id': pharmacieId,
    'abonnement_id': abonnementId,
    'montant': montant,
    'type_paiement': typePaiement,
    'statut_paiement': statutPaiement,
    'date': Timestamp.fromDate(date),
    'valide_par': validePar,
    'type_paiement_abonnement': typePaiementAbonnement,
    'reference': reference,
    'notes': notes,
  };
}

// ─── MÉDICAMENT ───────────────────────────────────────────────────────────────

class MedicamentModel {
  final String id;
  final String pharmacieId;
  final String nom;
  final String categorie;
  final String description;
  final double prixGrossiste;
  final double prixDetail;
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
    required this.prixGrossiste,
    required this.prixDetail,
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
    return MedicamentModel(
      id: id,
      pharmacieId: map['pharmacie_id'] ?? '',
      nom: map['nom'] ?? '',
      categorie: map['categorie'] ?? '',
      description: map['description'] ?? '',
      prixGrossiste: (map['prix_grossiste'] ?? 0).toDouble(),
      prixDetail: (map['prix_detail'] ?? 0).toDouble(),
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
    'fournisseur_id': fournisseurId,
    'fournisseur_nom': fournisseurNom,
    'image_url': imageUrl,
    'date_expiration': dateExpiration != null ? Timestamp.fromDate(dateExpiration!) : null,
    'code_barres': codeBarres,
    'seuil_alerte': seuilAlerte,
    'unites': unites.toMap(),
    'est_actif': estActif,
    'created_at': Timestamp.fromDate(createdAt),
    'updated_at': Timestamp.fromDate(updatedAt),
  };

  // Stock total en unité de base (comprimés/flacons)
  int get stockTotal => unites.totalUniteBase;

  bool get estEnRupture => stockTotal == 0;
  bool get estStockFaible => stockTotal > 0 && unites.totalBoites <= seuilAlerte;

  bool get estExpire {
    if (dateExpiration == null) return false;
    return DateTime.now().isAfter(dateExpiration!);
  }

  bool get expireBientot {
    if (dateExpiration == null) return false;
    final diff = dateExpiration!.difference(DateTime.now()).inDays;
    return diff > 0 && diff <= 30;
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
  final int cartonsParBoite;      // ex: 1 carton = 20 boites
  final int boitesParPlaquette;   // ex: 1 boite = 10 plaquettes
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
    return (cartons * cartonsParBoite * boitesParPlaquette * plaquettesParComprime) +
           (boites * boitesParPlaquette * plaquettesParComprime) +
           (plaquettes * plaquettesParComprime) +
           comprimes +
           flacons;
  }

  // Déduire une quantité vendue (en comprimés/unité base)
  UnitesStock deduire(int quantiteVendue, String unite) {
    // Conversion en comprimés pour calcul
    int totalActuel = totalUniteBase;
    int aDeduire = _convertirEnBase(quantiteVendue, unite);
    int restant = totalActuel - aDeduire;
    if (restant < 0) restant = 0;
    return _reconstruireDepuisBase(restant);
  }

  int _convertirEnBase(int quantite, String unite) {
    switch (unite) {
      case 'carton': return quantite * cartonsParBoite * boitesParPlaquette * plaquettesParComprime;
      case 'boite': return quantite * boitesParPlaquette * plaquettesParComprime;
      case 'plaquette': return quantite * plaquettesParComprime;
      case 'comprimes': return quantite;
      case 'flacon': return quantite;
      default: return quantite;
    }
  }

  UnitesStock _reconstruireDepuisBase(int totalBase) {
    int restant = totalBase;
    final perCarton = cartonsParBoite * boitesParPlaquette * plaquettesParComprime;
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
    if (plaquettes > 0) parts.add('$plaquettes plaquette${plaquettes > 1 ? 's' : ''}');
    if (comprimes > 0) parts.add('$comprimes comprimé${comprimes > 1 ? 's' : ''}');
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

  const FournisseurModel({
    required this.id,
    required this.pharmacieId,
    required this.nom,
    required this.telephone,
    required this.email,
    required this.adresse,
    required this.createdAt,
    this.notes,
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

// ─── CONFIG TARIFS (Super Admin) ──────────────────────────────────────────────

class TarifsConfig {
  final double fraisCreationCompte;
  final double abonnementMensuelDetaillant;
  final double abonnementMensuelGrossiste;
  final DateTime updatedAt;

  const TarifsConfig({
    required this.fraisCreationCompte,
    required this.abonnementMensuelDetaillant,
    required this.abonnementMensuelGrossiste,
    required this.updatedAt,
  });

  factory TarifsConfig.fromMap(Map<String, dynamic> map) {
    return TarifsConfig(
      fraisCreationCompte: (map['frais_creation_compte'] ?? 5000).toDouble(),
      abonnementMensuelDetaillant: (map['abonnement_mensuel_detaillant'] ?? 10000).toDouble(),
      abonnementMensuelGrossiste: (map['abonnement_mensuel_grossiste'] ?? 25000).toDouble(),
      updatedAt: (map['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'frais_creation_compte': fraisCreationCompte,
    'abonnement_mensuel_detaillant': abonnementMensuelDetaillant,
    'abonnement_mensuel_grossiste': abonnementMensuelGrossiste,
    'updated_at': Timestamp.fromDate(updatedAt),
  };

  double montantPourType(String type) {
    return type == 'grossiste' ? abonnementMensuelGrossiste : abonnementMensuelDetaillant;
  }
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
