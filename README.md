# Ma Pharmacie / PharmaFlow

Application Flutter de gestion de stock et de ventes, dédiée à une pharmacie.
Chaque pharmacie crée elle-même son compte Firebase Auth dans l’application.
Ses utilisateurs et appareils se connectent avec les mêmes identifiants pour
retrouver les mêmes données. Un autre compte correspond à une autre pharmacie.
Les comptes sont isolés par UID dans le projet Firebase configuré. Un projet
Firebase distinct par client reste possible à la distribution, mais l’inscription
ne crée pas de projet Firebase et n’exige aucun compte préparé par un technicien.

## Fonctionnalités

Préparation à la publication : `docs/GOOGLE_PLAY_RELEASE.md`.
Confirmation des emails et transition des comptes existants : `docs/EMAIL_VERIFICATION.md`.
APK de test du 16 octobre 2026 et installation : `docs/APK_TEST.md`.
Traitement des demandes de suppression : `docs/ACCOUNT_DELETION.md`.
Les coordonnées publiques de `admin/public/legal.json` doivent être validées
avant publication ; le déploiement Hosting refuse une configuration en brouillon.

- **Créer un compte** : email, mot de passe et confirmation, puis formulaire de
  la pharmacie. Connexion et récupération de mot de passe disponibles.
- Activation commerciale des nouveaux comptes après la vente, depuis un espace
  administrateur séparé. Pas d’abonnement ni de paiement en ligne. Le compte reste
  commun aux appareils de la pharmacie. Guide : `admin/README.md`.
- Au premier accès du compte autorisé : formulaire des informations de la pharmacie.
  Les appareils suivants retrouvent le même profil ; aucun choix grossiste/détaillant.
- Stock : création, modification, archivage, fournisseurs, code-barres par caméra,
  péremption, seuils et conditionnements.
- Prix d’achat distinct du prix de détail ; prix de gros facultatif.
  L’option **Paramètres > Ventes > Tarifs de gros**, désactivée par défaut, est
  commune aux appareils et nécessite une connexion pour être changée.
- La vente au détail est toujours disponible. Activer le gros affiche son tarif
  dans les fiches et le choix de prix dans la vente ; les unités de vente restent
  indépendantes du tarif. Un produit sans prix de gros ne peut pas être vendu en gros.
- Désactiver le gros conserve les prix existants et l’historique. Le panier revient
  au détail. Les ventes de gros déjà enregistrées hors ligne restent synchronisables :
  ce réglage commercial n’est pas une permission de sécurité.
- Vente, articles, déduction du stock et file d’envoi enregistrés ensemble dans SQLite.
  Contrôle des prix, quantités et péremptions ; flacons séparés des comprimés.
- Historique, indicateurs, fournisseurs et exports PDF.
- Sauvegarde locale chiffrée et restauration contrôlée depuis les options avancées.
- Synchronisation au démarrage, après écriture, au retour réseau, toutes les cinq
  minutes et manuellement ; état et erreurs visibles.
- Réception FCM et notifications locales. Pas encore d’alertes stock planifiées.

## Architecture et données

| Répertoire | Responsabilité |
|---|---|
| `lib/config` | Auth, inscription, profil, autorisations et routes |
| `lib/models` | Conversions Firestore/SQL, unités, stock et prix |
| `lib/repositories` | Contrôles d’accès, transactions métier et file d’envoi |
| `lib/local_database` | SQLite v2, migration, événements et codec JSON durable |
| `lib/services` | Synchronisation, réglages communs, notifications et exports |
| `lib/features` | Écrans Riverpod ; certains regroupés dans `screens_bundle.dart` |
| `test` | Tests modèles, accès, panier, SQLite, synchronisation et règles Firebase |
| `admin/public` | Tableau de bord web statique pour les coordonnées et activations |

Firestore :
- `pharmacies/{uid}` : profil, réglage booléen `tarifs_gros_actifs` et `access_status`.
- `clients/{uid}` : annuaire minimal, sans stocks, ventes ni jetons FCM ; coordonnées
  et statut accessibles à l’administrateur. Les nouveaux comptes sont `pending`.
- `account_admins/{uid}` : autorisation administrateur attribuée uniquement depuis
  un environnement privilégié, jamais par le navigateur ou l’application.
- `account_events/{id}` : historique immuable des décisions d’accès, réservé aux administrateurs.
- Sous-collections : `medicaments`, `fournisseurs`, `ventes`, `activites`,
  `notifications`. Aucun client ne peut accéder aux données d’un autre UID.

SQLite : `medicaments`, `fournisseurs`, `ventes`, `vente_items`, `activites`,
`sync_queue`. La table d’activités ne constitue pas encore un audit exhaustif.

Les règles et le routeur limitent les accès au profil portant l’UID du compte
connecté. Créer un compte ne donne jamais accès à une pharmacie existante.
`config/installation` n’est plus requis ni consulté. Les anciennes collections
`config`, `admins`, `paiements` et `abonnements` n’accordent plus aucun droit et
sont inaccessibles depuis les nouvelles règles.

## Java pour les compilations Android

Ce projet utilise Gradle 8.14. Utiliser un JDK 21 pour lancer Flutter et Gradle,
pas le JDK 25 fourni avec certaines installations récentes d'Android Studio.
Une erreur `What went wrong: 25.0.3` peut provenir de ce choix de JDK ; ajouter
`--enable-native-access=ALL-UNNAMED` ne corrige pas cette incompatibilité.

Sur le poste Windows actuel :

```powershell
flutter config --jdk-dir="C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot"
flutter analyze --suggestions --no-pub
```

Adapter le chemin au JDK 21 installé sur un autre poste. Ce réglage persiste
localement pour tous les projets Flutter ; redémarrer l'éditeur après modification.
Pour lancer Gradle directement, choisir aussi JDK 21 dans les paramètres Gradle
de l'IDE ou dans `JAVA_HOME`. Le réglage Flutter seul ne change pas le Java du
terminal ni celui des tâches Gradle lancées directement par Android Studio.

Références : [compatibilité Gradle/Java](https://docs.gradle.org/current/userguide/compatibility.html)
et [choix du JDK pour Flutter](https://docs.flutter.dev/release/breaking-changes/android-java-gradle-migration-guide).

## Mise en service d’une pharmacie

Ces étapes sont manuelles et ne sont **pas exécutées par les modifications du code**.

1. Utiliser Flutter **3.38+**, Dart **3.10+**, puis `flutter pub get`.
   Le stockage mobile cible Android/iOS ; Web/Windows/Linux ne sont pas validés.
2. Créer le projet Firebase de cette version et sa base Cloud Firestore. Configurer
   cette version avec `flutterfire configure` en vérifiant l’ID de projet choisi.
   Cela génère notamment `lib/firebase_options.dart`, le JSON Android et la
   configuration Apple. Ces fichiers sont ignorés par Git.
3. Dans Firebase Authentication, activer **Email/Password** et autoriser la création
   de comptes par les utilisateurs. Aucun compte client ni UID ne doit être saisi
   manuellement dans Firestore.
4. Conserver une configuration Firebase cohérente sur les appareils qui doivent
   partager un compte ; des projets différents ne partagent pas leurs identifiants.
5. Après sauvegarde et validation, déployer volontairement les règles et index
   sur le projet client :

   `firebase deploy --only firestore:rules,firestore:indexes --project YOUR_PROJECT_ID`

   **Cette commande modifie le serveur.** Ne pas laisser une base en mode test.
   Un fichier de règles local ne protège pas la base tant qu’il n’est pas déployé.
6. Le responsable ouvre **Créer un compte**, choisit son email et son mot de passe,
   puis complète les informations de sa pharmacie. Il attend l’activation après
   la vente, depuis le tableau de bord administrateur. Les autres utilisateurs ouvrent
   **Se connecter** avec ces mêmes identifiants, sans créer un nouveau compte.
   La première inscription exige Internet. Si la création du profil échoue après
   celle du compte Auth, se reconnecter permet de reprendre le formulaire : ne pas
   recréer le compte ni effacer les données.
7. Personnaliser le nom visible et les coordonnées de support, par exemple :

   `flutter run --dart-define="PHARMACIE_NOM=Pharmacie Exemple" --dart-define=SUPPORT_EMAIL=support@exemple.tld --dart-define=SUPPORT_WHATSAPP=243XXXXXXXXX`

   Le nom Dart n’isole pas les données et ne change pas le nom natif du lanceur,
   l’icône, le package Android ou le bundle Apple. Personnaliser aussi ces éléments
   et régénérer leur configuration Firebase pour chaque édition distribuée.

La configuration locale existante référence `mapharmacie-d56c2` : vérifier qu’il
s’agit bien de l’environnement destiné à ce client. Aucun autre environnement
client n’est automatiquement configuré.

### Compte commun

Aucune invitation ni approbation d’appareil n’est demandée. Les identifiants donnent
accès à la pharmacie depuis ses différents appareils ; toute autre personne qui
les obtient peut aussi se connecter. Les contrôles d’UID restent en place pour
empêcher un compte distinct d’accéder aux données d’un autre. Une réinitialisation change le mot de passe du compte
commun, pas celui d’un seul appareil. La réception des emails de récupération
reste à vérifier sur le projet client.

### Signature et plateformes

La release Android exige `android/key.properties`, d’après
`android/key.properties.example`, avec une vraie clé d’upload (jamais celle de debug).
Ne pas commiter les mots de passe ou les keystores. Sur Apple, finaliser les
fichiers Firebase, la signature, APNs et les capacités requises. Les permissions
caméra et notifications nécessitent une recette sur appareil réel.

Pour un APK Android plus léger, utiliser `flutter build apk --release --split-per-abi`.
Les fichiers sont générés dans `build/app/outputs/flutter-apk/` : `app-arm64-v8a-release.apk`
pour les appareils ARM 64 bits, `app-armeabi-v7a-release.apk` pour ARM 32 bits et
`app-x86_64-release.apk` pour x86-64. Installer uniquement celui adapté à l’appareil.
La configuration locale peut utiliser `android/pharmaflow-release.jks` avec
`android/key.properties` : conserver une copie sécurisée de ces deux fichiers privés,
exclus de Git. La même clé sera nécessaire pour signer les prochaines mises à jour.
Une release signée avec cette clé ne remplace pas directement une application signée
avec la clé debug. Avant toute désinstallation, synchroniser et exporter une sauvegarde
hors du téléphone ; désinstaller efface les données locales. Le build ne publie rien
sur Firebase ni sur Google Play.

## Migration

**Sauvegarder SQLite et Firestore avant déploiement et tester sur une copie.**

- Pour une pharmacie existante, conserver le même compte et le même UID afin de
  retrouver profil, données et opérations locales. `config/installation` est
  désormais ignoré et peut rester archivé. Ne pas recréer le compte ni changer
  son UID sans plan de migration.
- Les anciens champs de statut, catégorie et fin d’abonnement sont ignorés, pas
  effacés. Les anciennes collections de paiement restent sur le serveur, sans
  accès client. Aucun script de suppression de données n’est exécuté.
- Le gros reste désactivé par défaut, même pour un ancien profil « grossiste ».
  Ses tarifs existants sont conservés ; les nouveaux tarifs peuvent rester nuls.
- SQLite v1 migre vers v2 sans effacer les lignes : achat, unité, révision et
  métadonnées de synchronisation sont ajoutés. Aucun changement de version
  supplémentaire n’est nécessaire pour rendre le prix de gros facultatif.
- Le prix d’achat historique inconnu reste nul. Le renseigner avant toute vente :
  il n’est jamais déduit du tarif de gros. Vérifier unités et ratios existants.
- L’ancienne file au format Dart non fiable reste en statut `legacy` et bloque
  l’envoi. Sauvegarder et rapprocher ces opérations avec un technicien ; aucune
  réparation automatique risquant de doubler une vente n’est tentée.
- Les documents cloud incomplets doivent être rapprochés des sauvegardes locales.

## Synchronisation et sécurité

Les UUID et révisions permettent une reprise idempotente et détectent les écritures
concurrentes. Une vente et ses stocks sont envoyés dans une transaction Firestore.
Le téléchargement ne remplace pas les lignes locales en attente.

En cas de conflit entre appareils, **données et file sont conservées**. Les opérations
indépendantes continuent ; les opérations dépendantes restent en attente. Une erreur
réseau ou un refus Firebase arrête la tentative. Les documents locaux en attente ne
sont jamais remplacés par un téléchargement. Les nouvelles modifications des produits
en conflit sont bloquées jusqu’à vérification.

**Paramètres > Données > Suivi de synchronisation** affiche les opérations en attente.
Une vente peut être rapprochée explicitement : aperçu du stock serveur avant/après,
confirmation, puis nouvelle vérification dans une transaction. Le rapprochement conserve
les prix et la date de la vente et déduit ses quantités du stock actuel du serveur.
Un stock insuffisant, un conditionnement modifié, une fiche archivée, une opération
précédente liée ou une modification de fiche ultérieure empêchent ce rapprochement.
Les modifications de fiches et anciennes opérations `legacy` restent à traiter avec
le support, après sauvegarde : aucun bouton n’écrase aveuglément le stock serveur.

Chaque nouvelle opération envoyée crée un reçu immuable dans
`pharmacies/{uid}/activites/sync_{operation_id}`, dans la même transaction.
Son empreinte SHA-256 et l’identifiant d’opération permettent la reprise après une
interruption ou une restauration sans appliquer deux fois la même opération.
Les anciennes opérations sans reçu restent soumises aux contrôles de révision ;
elles peuvent nécessiter le support. Les règles actuelles de `activites` autorisent
ces reçus, sans ajout de collection ni modification de règles à déployer.

Une vente locale hors ligne peut toujours dépasser le stock réellement disponible
sur l’ensemble des appareils et être refusée à l’envoi. Cette évolution ne constitue
pas une réservation centralisée en temps réel. Ne pas désinstaller, vider la base ou
effacer la file tant que des opérations restent en attente.

Le compte doit avoir été connecté et son profil récupéré pour utiliser
les données mises en cache hors ligne. Une révocation ne peut pas effacer
instantanément les données déjà présentes sur un appareil déconnecté.

**Un projet dédié ne protège pas contre le vol du mot de passe du compte commun.**
Toute personne qui possède ces identifiants peut actuellement se connecter depuis
un nouvel appareil. L’approbation et la révocation individuelles des appareils ne
sont **pas encore implémentées**. Le compte partagé ne permet pas d’identifier
l’employé à l’origine de chaque vente. Les administrateurs du projet Firebase
conservent leurs accès techniques ; il ne s’agit pas d’un chiffrement de bout en bout.

SQLite reste non chiffré. Les données sont conservées à la déconnexion pour préserver
les opérations hors ligne et filtrées par propriétaire. Protéger les appareils.

## Sauvegarde et restauration

Ouvrir **Paramètres > Options avancées > Sauvegarde et restauration**.

- Créer une copie `.pfbackup` avec une phrase secrète d’au moins 12 caractères,
  distincte du mot de passe Firebase. Elle n’est pas conservée dans l’application.
  Sans cette phrase, la copie chiffrée est irrécupérable.
- Chiffrement authentifié AES-256-GCM ; clé dérivée par PBKDF2-HMAC-SHA256
  (600 000 itérations), sel aléatoire 16 octets et nonce aléatoire 12 octets, via
  `cryptography`. Les calculs s’effectuent hors du thread de l’interface.
- Seules les données locales du compte courant sont incluses : produits, fournisseurs,
  ventes et articles, activités locales et file d’envoi avec ses identifiants d’origine.
  Le profil Firebase, les fichiers/images distants et les identifiants de connexion
  ne sont pas inclus. Une copie locale n’est pas une sauvegarde du serveur.
- Enregistrer le fichier partagé sur un autre support. Un partage annulé ne signifie
  pas que la copie est conservée ailleurs. Les fichiers temporaires sont chiffrés.
- Pour restaurer, se connecter au **même compte**, choisir le fichier et sa phrase,
  vérifier le résumé puis confirmer. Les anciens JSON de format 1 / schéma 2 sont
  acceptés avec un avertissement : ils ne sont ni chiffrés ni authentifiés.
- La restauration est refusée si ce compte possède déjà des opérations locales en
  attente. Les autres comptes sont préservés. Un identifiant appartenant à un autre
  compte, une vente différente portant le même identifiant ou un fichier incohérent
  annule entièrement l’import, dans une transaction SQLite.
- Les fiches existantes sans opération importée sont préservées. Les fiches liées
  à des opérations importées retrouvent leur état local sauvegardé en attendant la
  synchronisation ; cela peut provoquer un conflit à résoudre. Les opérations sont
  restaurées dans leur ordre initial, avec leurs identifiants d’origine.
- Les documents déjà synchronisés de la copie sont réimportés localement, mais ne sont
  pas recréés automatiquement sur un serveur effacé. Ce flux vise la récupération
  d’un appareil, pas la reconstruction d’un projet Firebase détruit.
- Vérifier le suivi de synchronisation avant de reprendre les ventes. Ne pas reprendre
  une même file hors ligne sur plusieurs appareils à la fois. Les identifiants empêchent
  les doublons d’une même opération, pas deux saisies distinctes de la même vente réelle.
- Limites de cette version : 23 Mio de données avant chiffrement, fichier 32 Mio maximum,
  100 000 lignes importées. Au-delà, contacter le support ; aucune troncature silencieuse.

### Recette manuelle avant mise en service

1. Sur deux appareils de test du même compte, synchroniser un produit avec 10 boîtes.
2. Hors ligne, vendre 2 boîtes sur le premier et 3 sur le second. Reconnecter le premier,
   puis le second ; vérifier le conflit et rapprocher la seconde vente : stock final 5.
3. Refaire avec une quantité cumulée supérieure au stock ; le rapprochement doit être
   refusé, sans suppression de vente ni stock négatif.
4. Pendant un conflit, vendre un autre produit indépendant et vérifier son envoi.
5. Créer une copie avec des opérations hors ligne, la sauvegarder hors du téléphone,
   restaurer sur un appareil de test et vérifier les totaux après synchronisation.
6. Réimporter cette copie après synchronisation : aucune vente ni déduction supplémentaire.
7. Essayer une phrase erronée, un fichier altéré et un compte différent : aucun import.
8. Vérifier sur Android/iOS le sélecteur de fichier, le partage, le bouton Retour et
   la fermeture/réouverture de l’application avec une file non vide.

## Validation locale

### Lots et mouvements de stock

- Depuis **Stock → fiche produit → Lots et mouvements**, activer le suivi pour chaque
  produit souhaité. SQLite migre automatiquement du schéma 2 au schéma 3, sans modifier
  les quantités ni activer le suivi sur les produits existants.
- **Avant activation en production** : faire une sauvegarde, synchroniser les appareils,
  publier les règles `firestore.rules` de cette version et mettre tous les appareils à jour.
  Les règles bloquent les anciennes applications lorsqu’elles tentent de modifier un
  produit suivi par lots. Aucun déploiement Firebase n’est réalisé par les tests locaux.
- L’activation conserve le stock dans un lot « Stock initial » avec son coût d’achat
  de référence et sa date actuelle. Vérifier ces données avant activation. Le mode lots
  ne se désactive pas depuis l’interface ; conversions et unité tarifée restent figées.
- Réceptionner un lot avec numéro, quantité/unité, prix d’achat par unité réceptionnée,
  péremption obligatoire et fournisseur facultatif. Stockage en comprimés ou flacons.
  Le prix de vente reste celui du produit. Les bénéfices utilisent le coût réellement
  alloué aux lots de la vente, et non le coût de référence de la fiche.
- Les ventes consomment en priorité les lots qui expirent le plus tôt (FEFO). Les dates
  inconnues du stock initial restent vendables en dernier et sont signalées. Un lot est
  expiré à partir du lendemain de sa date. Les quantités expirées restent dans le stock
  physique mais sont exclues du disponible, des ventes et des calculs de seuils.
- Pour une casse, un retrait pour péremption ou un comptage, corriger le **nouveau total
  physique du lot**, en unités de base, avec un motif obligatoire. Ce n’est ni une vente
  ni un retour client. Les erreurs de lot/coût/date ne se réécrivent pas rétroactivement :
  corriger la quantité et enregistrer un nouveau lot correctement identifié si nécessaire.
- Les créations de stock, modifications de quantités, activations, réceptions, corrections
  et ventes créent des mouvements immuables, synchronisés atomiquement avec le stock.
  L’historique commence avec cette version ; aucun ancien mouvement n’est inventé.
  Avec le compte partagé, aucun vendeur individuel ne peut être identifié.
- Les soldes avant/après des mouvements correspondent à la saisie locale. En rapprochement,
  le serveur peut avoir un autre solde. Une vente conserve ses lots/coûts d’origine :
  si ces lots sont indisponibles, le rapprochement est refusé sans les remplacer en silence.
- Les lots sont intégrés aux PDF de stock et aux sauvegardes (schéma 3 ; import schéma 2
  encore accepté). Les allocations vendues restent dans l’historique et les mouvements.
- Limite : 200 lots conservés par produit. Lors d’une réception, les lots épuisés sortent
  de la fiche active ; les ventes et mouvements historiques ne sont pas supprimés.
  Un inventaire global, les retours clients et les tickets PDF restent des étapes séparées.

Recette : activer un produit test, réceptionner deux lots de dates et coûts différents,
vendre une quantité couvrant les deux, vérifier les coûts, les unités et les mouvements.
Tester un lot expiré, une correction à zéro, puis synchroniser sur un deuxième appareil.
Provoquer ensuite une vente concurrente sur le même lot : un conflit doit rester visible,
sans déduction supplémentaire ni réaffectation à un autre lot. Tester enfin la sauvegarde
et restauration des lots et des mouvements avant d’utiliser de vraies données.

### Commandes

```sh
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
firebase emulators:exec --only auth,firestore --project demo-pharmaflow-tests "node --test test/firestore_rules.test.cjs"
```

Le dernier test exige Node.js avec `fetch`/`node:test`, Firebase CLI et Java
compatibles. Il refuse tout hôte autre que les émulateurs locaux `127.0.0.1`.
Les tests Flutter de synchronisation utilisent un Firestore simulé. Ces tests ne
remplacent pas une recette réelle sur deux appareils (connexion, caméra, coupure
réseau, ventes concurrentes, notifications et partage).

## Interfaces adaptatives

- Portrait et paysage suivent les réglages de l'appareil. Les pages tiennent compte
  des zones réservées au système et le clavier ne doit pas masquer les formulaires.
- Sur grand écran (largeur ≥ 1000 et hauteur ≥ 500 pixels logiques), la navigation
  devient latérale et défilable. Sur téléphone, elle reste en bas et se masque
  lorsque le clavier est ouvert.
- Le contenu est centré, limité à 1200 pixels logiques (600 à 900 pour les formulaires
  et fiches). Les grilles et groupes de champs passent en colonnes selon l'espace
  disponible et la taille du texte choisie dans les réglages d'accessibilité.
- Les tests `test/responsive_screens_test.dart` parcourent les écrans, listes et
  formulaires sur petits téléphones, tablettes, grandes fenêtres et en paysage,
  avec texte jusqu'à 200 % et clavier simulé. `test/back_navigation_test.dart`
  vérifie aussi le changement de navigation lors d'un redimensionnement.

```sh
flutter test --no-pub test/responsive_screens_test.dart test/back_navigation_test.dart
```

Compléter ces tests par une recette sur téléphone et tablette réels : rotation,
clavier, agrandissement du texte, encoche, navigation gestuelle, caméra, sélecteurs
de fichiers et partage. Les tests de mise en page ne garantissent pas le comportement
des interfaces natives sur tous les modèles d'appareils.

## Limites restantes

- Pas d’approbation des appareils, de résolution guidée des conflits de fiches,
  d’export Word ou d’inventaire global rapproché. Le rapprochement guidé concerne
  uniquement les ventes compatibles ; les cas ambigus restent conservés pour le support.
- Les règles vérifient accès, forme et révisions, pas tous les calculs d’une vente.
  Un backend de confiance est nécessaire contre un client autorisé modifié.
- Montants en `double`, sans politique comptable complète d’arrondi.
- Lectures cloud non paginées ; pagination/synchronisation incrémentale à prévoir.
- Sauvegardes serveur, monitoring, confidentialité et publication à finaliser.
- Les mises à jour majeures des dépendances Firebase restent un chantier distinct.
