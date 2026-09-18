# Fix : Correction de l'ajout de médicament (Offline-First)

L'objectif est de débloquer l'ajout de médicaments en garantissant que la sauvegarde locale réussit toujours, même sans connexion ou si les données de la pharmacie sont en cours de chargement.

## Problèmes identifiés
- **Blocage Silencieux** : Si `currentPharmacieProvider` est nul (chargement en cours), la fonction s'arrête sans erreur visible.
- **Dépendance Réseau** : Le repository attend la réponse de Firestore avant de confirmer la réussite à l'utilisateur, ce qui peut bloquer l'UI si la connexion est instable.

## Modifications proposées

### [Composant] Stock (Feature)

#### [MODIFY] [medicament_form_screen.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/features/stock/presentation/medicament_form_screen.dart)
- Ajout d'une vérification explicite avec feedback (Snackbar) si les données de la pharmacie sont manquantes.
- Amélioration de la gestion des erreurs pour afficher précisément ce qui échoue.

### [Composant] Données (Repositories)

#### [MODIFY] [medicament_repository.dart](file:///E:/FLUTTER%20PROJECTS/pharmaflow/lib/repositories/medicament_repository.dart)
- **Priorité Locale** : Modification de `saveMedicament` pour que la partie Firestore soit exécutée en arrière-plan (sans `await` bloquant pour l'UI) ou via la queue de synchronisation si la connexion échoue.
- **Robustesse SQLite** : Sécurisation du mapping des colonnes pour éviter les erreurs de "column mismatch".

## Plan de vérification

### Vérification Manuelle
1. Tenter d'ajouter un médicament en mode avion (Simuler offline).
2. Tenter d'ajouter un médicament avec connexion.
3. Vérifier que la liste de stock se met à jour immédiatement après l'ajout.
