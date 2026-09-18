class AppConstants {
  // App info
  static const appName = String.fromEnvironment(
    'PHARMACIE_NOM',
    defaultValue: 'Ma Pharmacie',
  );
  static const appVersion = '1.0.0';

  // Firebase collections
  static const colPharmacies = 'pharmacies';
  static const colUsers = 'users';
  static const colMedicaments = 'medicaments';
  static const colVentes = 'ventes';
  static const colFournisseurs = 'fournisseurs';
  static const colActivites = 'activites';
  static const colConfig = 'config';
  static const colNotifications = 'notifications';

  // Sqflite tables
  static const tblMedicaments = 'medicaments';
  static const tblVentes = 'ventes';
  static const tblVenteItems = 'vente_items';
  static const tblFournisseurs = 'fournisseurs';
  static const tblSyncQueue = 'sync_queue';
  static const tblActivites = 'activites';

  // Stock
  static const seuilDefaut = 10;

  // Unités hiérarchie
  static const unites = ['carton', 'boite', 'plaquette', 'comprimes', 'flacon'];
}

class TypeVente {
  static const detail = 'detail';
  static const gros = 'gros';
}

class TypeActivite {
  static const ajoutMedicament = 'ajout_medicament';
  static const modifStock = 'modif_stock';
  static const vente = 'vente';
  static const suppressionProduit = 'suppression_produit';
  static const modifPrix = 'modif_prix';
  static const connexion = 'connexion';
}
