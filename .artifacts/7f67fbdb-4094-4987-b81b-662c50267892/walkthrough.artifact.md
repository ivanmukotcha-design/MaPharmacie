# Correction de l'erreur GlobalKey et Stabilisation

L'erreur `GlobalKey was used multiple times` a été résolue en stabilisant la navigation et en sécurisant l'identification des widgets lors des reconstructions.

## Changements effectués

### Stabilisation du Routeur
Dans [router.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/config/router.dart), j'ai remplacé l'utilisation de `ref.watch` par un `RouterNotifier` utilisant `refreshListenable`.
- **Pourquoi ?** Auparavant, chaque changement d'état (auth ou pharmacie) détruisait et recréait complètement l'instance de `GoRouter`, ce qui forçait Flutter à reconstruire toute l'arborescence des pages, causant des conflits de clés globales. Maintenant, le routeur est stable et se contente de rafraîchir ses redirections.

### Identification des Widgets (Settings)
Dans [screens_bundle.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/features/screens_bundle.dart), j'ai ajouté des `ValueKey` uniques à chaque élément de la liste des paramètres.
- **Pourquoi ?** Cela aide le moteur de rendu de Flutter à suivre précisément chaque widget (notamment les effets d'encre `ListTile`) lors des mises à jour d'interface, évitant ainsi l'erreur "ink renderer".

### Optimisation du Root Builder
Dans [main.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/main.dart), j'ai ajouté une clé stable à l'`AnnotatedRegion` globale pour éviter toute ambiguïté lors des changements de thème système.

## Résultat
L'application devrait maintenant être stable, sans erreurs de console lors de l'accès aux paramètres ou de la navigation.

> [!IMPORTANT]
> Comme pour les changements précédents, un **Hot Restart** est nécessaire pour que la nouvelle structure du routeur soit prise en compte.
