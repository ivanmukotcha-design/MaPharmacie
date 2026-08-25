class AppConstants {
  // App info
  static const appName = 'Ma Pharmacie';
  static const appVersion = '1.0.0';

  // Firebase collections
  static const colPharmacies = 'pharmacies';
  static const colUsers = 'users';
  static const colMedicaments = 'medicaments';
  static const colVentes = 'ventes';
  static const colFournisseurs = 'fournisseurs';
  static const colPaiements = 'paiements';
  static const colAbonnements = 'abonnements';
  static const colActivites = 'activites';
  static const colConfig = 'config';
  static const colNotifications = 'notifications';

  // Config doc
  static const docTarifs = 'tarifs';

  // Sqflite tables
  static const tblMedicaments = 'medicaments';
  static const tblVentes = 'ventes';
  static const tblVenteItems = 'vente_items';
  static const tblFournisseurs = 'fournisseurs';
  static const tblSyncQueue = 'sync_queue';
  static const tblActivites = 'activites';

  // Abonnement
  static const joursAvertissement10 = 10;
  static const joursAvertissement5 = 5;
  static const joursAvertissement1 = 1;

  // Stock
  static const seuilDefaut = 10;

  // Unités hiérarchie
  static const unites = ['carton', 'boite', 'plaquette', 'comprimes', 'flacon'];
}

class PharmacieStatut {
  static const actif = 'actif';
  static const expire = 'expire';
  static const suspendu = 'suspendu';
  static const attentePaiement = 'attente_paiement';
}

class TypePharmacie {
  static const detaillant = 'detaillant';
  static const grossiste = 'grossiste';
}

class TypeVente {
  static const detail = 'detail';
  static const gros = 'gros';
}

class TypePaiement {
  static const airtelMoney = 'airtel_money';
  static const mpesa = 'm_pesa';
}

class StatutPaiement {
  static const complet = 'complet';
  static const partiel = 'partiel';
  static const enAttente = 'en_attente';
}

class TypeActivite {
  static const ajoutMedicament = 'ajout_medicament';
  static const modifStock = 'modif_stock';
  static const vente = 'vente';
  static const suppressionProduit = 'suppression_produit';
  static const modifPrix = 'modif_prix';
  static const renouvellementAbonnement = 'renouvellement_abonnement';
  static const connexion = 'connexion';
}
