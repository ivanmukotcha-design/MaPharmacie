# Administration des comptes PharmaFlow

État de la première publication et APK validé : [publication du 3 octobre 2026](DEPLOYMENT.md).

Première version : connexion personnelle, récapitulatif des fiches chargées,
recherche locale et filtres, coordonnées clients, activation après vente,
suspension/réactivation avec confirmation et motif, historique non modifiable.
Il n’y a ni paiement en ligne, ni abonnement, ni accès aux stocks, ventes,
bénéfices, sauvegardes ou jetons FCM. L’interface ne peut pas se connecter à la
place d’un client. Les dernières connexions, appareils, licences commerciales
et tickets d’assistance ne font pas encore partie de cette version.

## Hébergement et coûts

Site statique sur **Firebase Hosting** (pas App Hosting), avec Authentication
Email/Password et Firestore. Pas de Cloud Functions, serveur permanent, SMS,
Analytics ni service payant supplémentaire requis par cette implémentation.
Les quotas du projet restent communs avec l’application : aucune promesse de
gratuité illimitée. L’annuaire se charge par pages de 100, sur demande, sans
écoute temps réel globale. La recherche et les compteurs indiquent clairement
qu’ils portent sur les fiches chargées. L’historique affiche les 30 dernières
interventions, les autres restent conservées sur le serveur.

Les modules Firebase Web sont épinglés en version 12.19.0, téléchargés depuis
le CDN officiel Google. La configuration publique provient de
`/__/firebase/init.json` sur le site Hosting choisi. Aucune clé de compte de
service ni secret administrateur ne doit être ajouté aux fichiers publics.

## Droits et confidentialité

- `account_admins/{uid}` avec `enabled: true` autorise ce compte personnel. Les
  anciens documents `admins` n’accordent toujours aucun droit. Aucun utilisateur,
  même administrateur du tableau de bord, ne peut attribuer ce rôle depuis le client.
- L’administrateur lit uniquement `clients` et `account_events`, pas les documents
  `pharmacies` complets ni leurs sous-collections métier. Les règles lui permettent
  de modifier uniquement les champs d’accès du profil, avec la modification
  correspondante dans l’annuaire et l’historique, dans une transaction atomique.
- Les coordonnées sont projetées depuis le profil authentifié par l’application.
  Les clients ne peuvent pas modifier leur statut, créer un historique ou lire
  l’annuaire des autres pharmacies.
- Le rôle est recontrôlé côté serveur à chaque action et surveillé dans le navigateur.
  Sa révocation ferme l’espace. La session est limitée à l’onglet ; Firestore
  n’utilise pas de persistance disque dans ce tableau de bord.
- Le propriétaire technique du projet Firebase conserve ses pouvoirs dans la
  console Google. Ces restrictions concernent le tableau de bord, pas les pouvoirs
  IAM du propriétaire. Protéger aussi le compte Google avec une authentification
  renforcée. Le tableau de bord v1 utilise email/mot de passe ; MFA non intégré.

## Statuts et appareils hors connexion

- Nouveau profil : `access_status: pending`. Aucune lecture ou écriture métier
  tant que l’administrateur n’a pas confirmé la vente et activé le compte.
- `active` : fonctionnement normal sur tous les appareils du compte partagé.
- `suspended` : nouvelles écritures refusées côté serveur. Dans l’application
  mise à jour, accès limité au support et à la création d’une sauvegarde locale.
  Aucune suppression de données ou d’opérations en attente ; restauration désactivée.
- Une suspension n’est pas un indicateur de dernière connexion. Un appareil
  déconnecté peut continuer avec son dernier statut connu. Les écritures cloud
  seront refusées à sa reconnexion si le compte est suspendu. Il ne s’agit pas
  d’une protection DRM ni d’une révocation immédiate hors ligne.
- L’activation ne met pas en place de date d’expiration. L’historique conserve
  auteur, date serveur, ancien/nouveau statut, motif et numéro de révision.

## Transition des comptes existants

**Ne pas publier les règles sans préparer les appareils et le compte administrateur.**

Les profils existants sans `access_status` gardent leur accès (`active`) : ils
ne sont ni suspendus ni effacés automatiquement. Les anciens champs `statut` et
`abonnement_fin` restent ignorés. Au prochain chargement en ligne du profil dans
la nouvelle application, ses seules coordonnées sont copiées dans `clients`.
Ils apparaissent alors dans le tableau de bord. L’activation initiale d’un ancien
compte reste « Non renseignée » plutôt que d’inventer une date de vente.

Un client utilisant uniquement l’ancien APK n’apparaîtra donc pas automatiquement
dans l’annuaire. Faire installer la mise à jour et reconnecter chaque pharmacie
avant de considérer l’annuaire comme exhaustif. Les nouveaux profils créés par
un ancien APK seront refusés par les nouvelles règles : distribuer le nouvel APK
en coordination avec la publication. L’APK compilé avant cette fonctionnalité
ne contient pas le nouveau parcours d’activation.

Une copie locale du projet et ces modifications ne changent rien en production.
Les règles, index et site doivent être déployés volontairement. Aucun compte réel
n’est créé, activé, suspendu ou migré par les tests.

## Première mise en ligne

1. Sauvegarder et synchroniser les pharmacies existantes. Vérifier le projet
   cible : actuellement `mapharmacie-d56c2`. Ne pas lancer `firebase init` sur ce
   dépôt, car la configuration Hosting/Firestore est déjà préparée.
2. Dans Firebase Console > Authentication > Users, créer un **compte personnel
   administrateur distinct** des comptes de pharmacie partagés, avec une adresse email
   maîtrisée et un mot de passe fort. Utiliser la récupération de mot de passe
   pour choisir son propre secret ; ne jamais le communiquer dans une discussion.
3. Copier son UID. Dans Firestore Console, créer `account_admins/UID_ADMIN` avec
   un champ **booléen** `enabled` égal à `true`. Ne pas créer de rôle pour un UID
   de pharmacie partagé avec un client ou un employé. Un compte personnel déjà
   associé à une pharmacie de test peut être conservé, à condition que ses
   identifiants restent strictement privés et que cette pharmacie ne soit jamais
   cédée à un client. Cette opération est réservée au propriétaire Firebase.
4. Après validation, publier depuis la racine du dépôt :

   ```sh
   firebase deploy --only firestore:rules,firestore:indexes,hosting --project mapharmacie-d56c2
   ```

   Cela modifie le serveur et publie sur le site Hosting par défaut de ce projet.
   Vérifier qu’il n’héberge pas déjà un autre site avant de l’écraser. Dans ce cas,
   créer un site Hosting dédié et configurer une cible avant toute publication.
5. Attendre que l’index `account_events` (`client_id`, `revision`) soit prêt.
   Utiliser l’URL Hosting retournée par Firebase CLI. Se connecter au tableau de
   bord avec le compte administrateur, pas un compte client.
6. Tester une pharmacie fictive : inscription dans le nouvel APK, attente,
   activation dans le tableau de bord, accès sur deux appareils, suspension,
   sauvegarde locale puis réactivation. Vérifier le scénario hors connexion.

Pour retirer les droits administrateur, passer `enabled` à `false` dans la console.
Ne jamais désactiver les règles ou ajouter `allow read, write: if true` pour résoudre
un problème d’accès. Conserver la signature Android existante lors de la compilation.

## Compilation Android sur un PC Windows à mémoire limitée

La version à distribuer après l'activation des comptes est `1.0.1+2` ou ultérieure.
Conserver `android/key.properties` et la clé de signature existante, sans les
communiquer ni les ajouter au dépôt. Synchroniser et sauvegarder avant toute
mise à jour. Ne pas désinstaller une version existante pour résoudre une erreur
de signature : cela peut effacer ses données locales.

Avec Java 21 installé au chemin ci-dessous, cette commande compile seulement
l'APK ARM64 et limite Gradle à un worker. Les variables ne concernent que la
session PowerShell courante ; adapter le chemin Java si nécessaire.

```powershell
$env:JAVA_HOME = 'C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot'
$env:GRADLE_OPTS = '-Dorg.gradle.java.home="C:/Program Files/Eclipse Adoptium/jdk-21.0.11.10-hotspot" -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.jvmargs="-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m"'
[Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_kotlin.incremental', 'false', 'Process')
[Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_kotlin.compiler.execution.strategy', 'in-process', 'Process')
flutter build apk --release --split-per-abi --target-platform android-arm64 --no-pub
```

Utiliser cette commande après installation des dépendances. Le résultat attendu
est `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Vérifier la réussite
de la compilation, sa version et sa signature avant distribution. Les APK des
autres architectures éventuellement présents dans ce dossier ne sont pas mis
à jour par cette commande et ne doivent pas être confondus avec la nouvelle version.

## Vérifications locales

À la racine du dépôt, avec Node.js et Java compatibles avec Firebase CLI :

```sh
node --test test/admin_dashboard_test.mjs
flutter test --no-pub
npm --prefix admin ci --ignore-scripts
firebase emulators:exec --only auth,firestore --project demo-pharmaflow-tests "node --test test/firestore_rules.test.cjs && npm --prefix admin run test:browser"
```

Les tests navigateur utilisent Microsoft Edge installé, en mode headless. Adapter
`channel` dans `playwright.config.mjs` sur une autre machine si nécessaire. Ils
utilisent seulement des comptes fictifs et refusent des hôtes d’émulateurs non locaux.

Pour un aperçu manuel, démarrer les émulateurs locaux puis `npm --prefix admin run serve`
et ouvrir `http://127.0.0.1:4173/?emulators=1`. Le mode émulateur est accepté uniquement
sur localhost/127.0.0.1, avec un projet `demo-`. Il ne fournit pas de bouton public
d’attribution des droits administrateur. Le serveur local est distinct de Firebase
Hosting et ne doit pas servir à héberger la production.

Références : [SDK Web](https://firebase.google.com/docs/web/setup),
[configuration Hosting](https://firebase.google.com/docs/hosting/reserved-urls),
[tarifs](https://firebase.google.com/pricing).
