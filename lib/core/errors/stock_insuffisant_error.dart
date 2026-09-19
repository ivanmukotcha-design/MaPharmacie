class StockInsuffisantError extends StateError {
  final String produit;
  final int quantiteDemandee;
  final int quantiteDisponible;
  final String unite;

  StockInsuffisantError({
    required this.produit,
    required this.quantiteDemandee,
    required this.quantiteDisponible,
    required this.unite,
  }) : super(
         '$produit\n\n'
         'Quantité demandée : ${_quantite(quantiteDemandee, unite)}\n'
         'Stock disponible : ${_quantite(quantiteDisponible, unite)}\n\n'
         'Réduisez la quantité ou choisissez une autre unité.',
       );

  static String _quantite(int quantite, String unite) {
    final pluriel = quantite > 1;
    final libelle = switch (unite) {
      'carton' => pluriel ? 'cartons' : 'carton',
      'boite' => pluriel ? 'boîtes' : 'boîte',
      'plaquette' => pluriel ? 'plaquettes' : 'plaquette',
      'comprimes' => pluriel ? 'comprimés' : 'comprimé',
      'flacon' => pluriel ? 'flacons' : 'flacon',
      _ => pluriel ? 'unités' : 'unité',
    };
    return '$quantite $libelle';
  }
}
