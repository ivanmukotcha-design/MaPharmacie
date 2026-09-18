import 'package:pharmaflow/models/models.dart';

MedicamentModel medicament({
  String id = 'med-1',
  String pharmacieId = 'pharma-1',
  UnitesStock unites = const UnitesStock(boites: 10),
  DateTime? expiration,
  double? prixAchat = 50,
  double? prixGrossiste = 80,
  String unitePrix = 'boite',
}) {
  return MedicamentModel(
    id: id,
    pharmacieId: pharmacieId,
    nom: 'Produit $id',
    categorie: 'Autre',
    description: '',
    prixGrossiste: prixGrossiste,
    prixDetail: 100,
    prixAchat: prixAchat,
    unitePrix: unitePrix,
    fournisseurId: '',
    fournisseurNom: '',
    seuilAlerte: 2,
    unites: unites,
    estActif: true,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
    dateExpiration: expiration,
  );
}

VenteModel vente({
  String id = 'sale-1',
  String pharmacieId = 'pharma-1',
  List<VenteItemModel>? items,
  String typeVente = 'detail',
}) {
  final lignes = items ?? [venteItem()];
  final total = lignes.fold(0.0, (sum, item) => sum + item.sousTotal);
  return VenteModel(
    id: id,
    pharmacieId: pharmacieId,
    typeVente: typeVente,
    items: lignes,
    totalHT: total,
    totalTTC: total,
    benefice: lignes.fold(0.0, (sum, item) => sum + item.beneficeItem),
    date: DateTime.now(),
  );
}

VenteItemModel venteItem({
  String id = 'med-1',
  int quantite = 2,
  String unite = 'boite',
  double prix = 100,
  double cout = 50,
}) => VenteItemModel(
  medicamentId: id,
  medicamentNom: 'Produit $id',
  quantite: quantite,
  unite: unite,
  prixUnitaire: prix,
  prixAchat: cout,
  sousTotal: prix * quantite,
);

PharmacieModel pharmacie({bool tarifsGrosActifs = false}) => PharmacieModel(
  id: 'pharma-1',
  code: 'PHR-pharma-1',
  nom: 'Pharmacie',
  username: 'pharma',
  email: 'pharma@example.com',
  telephone: '123',
  adresse: 'Rue',
  ville: 'Ville',
  pays: 'CD',
  tarifsGrosActifs: tarifsGrosActifs,
  proprietaireNom: 'Propriétaire',
  createdAt: DateTime(2025),
);
