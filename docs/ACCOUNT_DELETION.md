# Traitement manuel des demandes de suppression

Cette procédure est réservée au responsable habilité du projet. Elle décrit des
opérations destructives qui ne sont **pas exécutées** par l'application, les tests
ou la préparation Google Play. Aucun bouton du tableau de bord ne réalise encore
cet effacement. Tester d'abord sur un compte fictif dans un environnement isolé.

## Avant l'ouverture au public

1. Définir qui surveille l'adresse de support, comment les demandes sont enregistrées
   et quel délai de réponse et de réalisation peut être tenu.
2. Déterminer les éventuelles obligations de conservation applicables à l'activité
   et au pays, puis indiquer les données concernées, la raison et la durée dans la
   politique publique. Ne pas inventer une durée légale universelle.
3. Vérifier les sauvegardes, exports administratifs et éventuelle récupération
   temporelle Firestore réellement activés. Définir leur expiration et empêcher
   qu'une restauration réintroduise les comptes supprimés.
4. Tester la procédure complète, sa vérification et sa confirmation au demandeur.

## Réception et autorisation

- Accuser réception sans demander de mot de passe, de base complète ni de dossier médical.
- Identifier le compte par son email et son UID dans Firebase Authentication,
  puis vérifier que la pharmacie correspond. Ne jamais sélectionner un UID par
  simple ressemblance de nom.
- Vérifier l'identité et l'habilitation à agir pour **toute** la pharmacie : le
  même compte peut être utilisé sur plusieurs appareils. Proposer une vérification
  raisonnable alternative si le responsable n'a plus accès à son email.
- Confirmer le périmètre, les éventuelles conservations justifiées et le délai.
  Une sauvegarde facultative n'est pas une condition pour demander la suppression.
  La suspension ou l'absence d'activation commerciale ne doit pas empêcher la demande.
- Si le compte possède un rôle dans `account_admins`, arrêter la procédure ordinaire
  et organiser séparément la continuité administrative. Ne pas supprimer par erreur
  le dernier administrateur ou confondre compte Firebase Auth et propriétaire Google Cloud.

## Exécution contrôlée

1. Consigner l'autorisation et le périmètre minimal nécessaire, sans dupliquer les
   stocks ou ventes dans un journal de support.
2. Suspendre l'accès aux écritures métier par le mécanisme administratif existant,
   puis désactiver l'utilisateur Firebase Auth et révoquer ses jetons de renouvellement
   depuis un environnement privilégié. La révocation ne garantit pas l'invalidation
   immédiate de tous les jetons ID déjà émis : contrôler l'accès effectif et attendre
   leur expiration si nécessaire avant de finaliser le nettoyage.
3. Les règles actuelles doivent être examinées pour chaque chemin encore accessible,
   notamment l'annuaire et le profil. Prévenir toute recréation pendant l'effacement.
   Ne pas réactiver le compte à la fin et ne pas se contenter de supprimer Auth en premier.
4. Supprimer récursivement `pharmacies/{uid}` **et toutes ses sous-collections**, y
   compris celles inconnues d'une ancienne version. Supprimer le seul document parent
   n'efface pas ses sous-collections. Inclure stocks, lots, ventes, fournisseurs,
   activités, notifications et jetons présents dans ce sous-arbre.
5. Supprimer `clients/{uid}` et rechercher les données associées dans `account_events`
   par `client_id`. Effacer ou anonymiser les événements suivant la politique approuvée ;
   une conservation éventuelle doit avoir un motif et une échéance communiqués.
   Rechercher également les éventuels fichiers Storage, exports ou anciens schémas
   réellement présents : une dépendance Storage ne prouve pas qu'il existe des fichiers.
6. Supprimer l'utilisateur Firebase Authentication quand le nettoyage est maîtrisé.
   Vérifier de nouveau l'absence des documents et sous-collections après expiration
   des sessions susceptibles d'écrire. Il n'existe pas de transaction unique englobant
   Auth, Firestore et les sauvegardes : traiter et vérifier les reprises après erreur.
7. Gérer les copies administratives et la rétention des sauvegardes conformément à
   la politique. Ne pas promettre un effacement immédiat d'une archive qui ne permet
   pas la suppression ciblée ; préciser sa restriction d'accès et son expiration réelle.

Utiliser uniquement un outil privilégié audité, avec une sélection explicite du
projet et de l'UID. Ne jamais déployer une clé Admin SDK dans l'application ou le
site, ni ouvrir les règles Firestore pour faciliter cette opération. Le rôle du
tableau de bord commercial ne doit pas donner accès aux données métier.

## Vérification et clôture

- Vérifier l'absence du compte Auth, des données actives et des sous-collections,
  et contrôler qu'un ancien appareil connecté ne peut plus écrire sur cet UID.
- Vérifier qu'une autre pharmacie n'a pas été affectée.
- Confirmer au demandeur ce qui est effacé, ce qui reste éventuellement conservé,
  pourquoi et jusqu'à quand. Ne pas annoncer un succès après un effacement partiel.
- Expliquer que les appareils hors ligne et les PDF/sauvegardes déjà exportés ne
  sont pas effacés à distance. Leur responsable doit supprimer les copies locales
  concernées. Une désinstallation seule n'efface pas le compte dans Firebase.
- Ne conserver qu'une preuve de traitement proportionnée, avec sa propre durée
  de conservation. La procédure doit couvrir aussi les comptes jamais activés.

Références : [demandes de suppression Google Play](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr),
[sessions Firebase Auth](https://firebase.google.com/docs/auth/admin/manage-sessions),
[suppression Firestore et sous-collections](https://firebase.google.com/docs/firestore/manage-data/delete-data).
