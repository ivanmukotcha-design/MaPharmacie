# Correction de l'erreur GlobalKey et Stabilisation du Router

L'erreur `GlobalKey was used multiple times inside one widget's child list [ink renderer]` est généralement causée par la recréation complète de l'arborescence des widgets lors d'un changement d'état global, ce qui arrive ici à cause de la configuration actuelle de `GoRouter`.

## Modifications proposées

### [Composant] Configuration (Config)

#### [MODIFY] [router.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/config/router.dart)
- Modification du `routerProvider` pour qu'il soit stable. Actuellement, il utilise `ref.watch`, ce qui recrée une nouvelle instance de `GoRouter` à chaque changement d'authentification ou de pharmacie. Cela provoque une reconstruction complète du Navigator et des erreurs de clés globales lors des transitions.
- Utilisation d'un `refreshListenable` pour notifier `GoRouter` des changements d'état sans détruire l'instance du routeur.

### [Composant] Paramètres (Settings)

#### [MODIFY] [screens_bundle.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/features/screens_bundle.dart)
- Ajout de `ValueKey` explicites sur les éléments de liste dans `SettingsScreen`. Cela aidera Flutter à identifier correctement les widgets lors des reconstructions et évitera les conflits de rendu d'encre (`ink renderer`).

### [Composant] Main (Root)

#### [MODIFY] [main.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/main.dart)
- Optimisation du `builder` de `MaterialApp` pour s'assurer que `AnnotatedRegion` n'est pas recréé inutilement avec des clés conflictuelles.

## Plan de vérification

### Vérification Manuelle
- Lancer l'application et naviguer vers les paramètres.
- Vérifier que l'erreur `GlobalKey was used multiple times` ne s'affiche plus dans la console.
- Confirmer que la navigation entre les onglets reste fluide.
