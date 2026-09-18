# Ma Pharmacie / PharmaFlow

Application Flutter de gestion de stock et de ventes, dédiée à une pharmacie.
Chaque pharmacie crée elle-même son compte Firebase Auth dans l’application.
Ses utilisateurs et appareils se connectent avec les mêmes identifiants pour
retrouver les mêmes données. Un autre compte correspond à une autre pharmacie.
Les comptes sont isolés par UID dans le projet Firebase configuré. Un projet
Firebase distinct par client reste possible à la distribution, mais l’inscription
ne crée pas de projet Firebase et n’exige aucun compte préparé par un technicien.

## Fonctionnalités

- **Créer un compte** : email, mot de passe et confirmation, puis formulaire de
  la pharmacie. Connexion et récupération de mot de passe disponibles.
- Pas d’invitation, de validation manuelle, de connexion Google, d’abonnement, de
  paiement ou de super-administrateur. Le compte est commun aux appareils de la pharmacie.
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
- Historique, indicateurs, fournisseurs, exports Excel et sauvegarde JSON locale.
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

Firestore :
- `pharmacies/{uid}` : profil et réglage booléen `tarifs_gros_actifs`.
- Sous-collections : `medicaments`, `fournisseurs`, `ventes`, `activites`,
  `notifications`. Aucun client ne peut accéder aux données d’un autre UID.

SQLite : `medicaments`, `fournisseurs`, `ventes`, `vente_items`, `activites`,
`sync_queue`. La table d’activités ne constitue pas encore un audit exhaustif.

Les règles et le routeur limitent les accès au profil portant l’UID du compte
connecté. Créer un compte ne donne jamais accès à une pharmacie existante.
`config/installation` n’est plus requis ni consulté. Les anciennes collections
`config`, `admins`, `paiements` et `abonnements` n’accordent plus aucun droit et
sont inaccessibles depuis les nouvelles règles.

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
   puis complète les informations de sa pharmacie. Les autres utilisateurs ouvrent
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

En cas de conflit entre appareils ou de refus serveur, **données et file sont
conservées**, l’envoi s’arrête avec une erreur visible. Une vente locale hors ligne
peut donc ne pas être acceptée sur le serveur. Ne pas désinstaller, vider la base
ou effacer la file : exporter une sauvegarde et rapprocher stocks et ventes.
La résolution des conflits reste manuelle, et non transparente entre appareils.

Le compte doit avoir été connecté et son profil récupéré pour utiliser
les données mises en cache hors ligne. Une révocation ne peut pas effacer
instantanément les données déjà présentes sur un appareil déconnecté.

**Un projet dédié ne protège pas contre le vol du mot de passe du compte commun.**
Toute personne qui possède ces identifiants peut actuellement se connecter depuis
un nouvel appareil. L’approbation et la révocation individuelles des appareils ne
sont **pas encore implémentées**. Le compte partagé ne permet pas d’identifier
l’employé à l’origine de chaque vente. Les administrateurs du projet Firebase
conservent leurs accès techniques ; il ne s’agit pas d’un chiffrement de bout en bout.

SQLite et les sauvegardes JSON ne sont pas chiffrés. Les données sont conservées à
la déconnexion pour préserver les opérations hors ligne et filtrées par propriétaire.
Protéger les appareils et les sauvegardes.

## Validation locale

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

## Limites restantes

- Pas d’approbation des appareils, de résolution guidée des conflits, de restauration
  JSON automatique, d’export Word, de lots ou d’inventaire rapproché.
- Les règles vérifient accès, forme et révisions, pas tous les calculs d’une vente.
  Un backend de confiance est nécessaire contre un client autorisé modifié.
- Montants en `double`, sans politique comptable complète d’arrondi.
- Lectures cloud non paginées ; pagination/synchronisation incrémentale à prévoir.
- Sauvegardes serveur, monitoring, confidentialité et publication à finaliser.
- Les mises à jour majeures des dépendances Firebase restent un chantier distinct.
