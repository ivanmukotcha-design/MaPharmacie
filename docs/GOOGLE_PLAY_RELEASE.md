# Préparation de Google Play

Les pages publiques ont été publiées sur Firebase Hosting le 16 octobre 2026,
avec l'accord d'Ivan Mukotcha pour son nom et son email publics. L'application
n'est pas encore publiée sur Google Play. Cette préparation ne garantit pas
l'acceptation par Google. Les points non cochés doivent être
vérifiés sur le produit final et dans Play Console.

## Informations publiques à confirmer

- [x] Renseigner `publisherName`, `supportEmail` et `effectiveDate` dans
  `admin/public/legal.json`. Ne pas publier une adresse personnelle sans accord.
- [ ] Vérifier l'adéquation de la politique aux obligations réelles : hébergement, accès technique du propriétaire
  Firebase, absence de chiffrement applicatif de SQLite, conservation, sauvegardes,
  transferts et traitement des demandes. Adapter au pays et à l'activité réels.
- [ ] Choisir un délai de réponse et de traitement réaliste, le communiquer dans la
  politique, organiser la surveillance de la boîte support et tester la procédure
  décrite dans `ACCOUNT_DELETION.md` sur une pharmacie fictive.
- [x] Enregistrer l'accord de publication avec `approvedForPublication: true`.
  Cet accord ne certifie pas la conformité juridique ni la réalisation des tests
  de traitement manuel des demandes, qui restent à effectuer.

Le même JSON est embarqué dans Flutter et servi par le site. Une modification du
site ne met pas automatiquement à jour le texte embarqué dans les APK installés.
Le contrôle `node scripts/check_public_information.mjs` refuse les coordonnées
manquantes ou une politique non approuvée. Il s'exécute avant le déploiement Hosting.
Ce contrôle de structure n'est pas une validation juridique.

Les deux pages publiques sont accessibles sans connexion :

- `https://mapharmacie-d56c2.web.app/confidentialite.html`
- `https://mapharmacie-d56c2.web.app/suppression-compte.html`

Après déploiement, sept fichiers publics ont été comparés à leur version locale.
Les deux pages, les coordonnées et le lien email ont été vérifiés sans connexion
dans le navigateur à 320 et 1280 pixels. Aucun email n'a été envoyé et aucune
donnée client ni règle Firestore n'a été modifiée. Seule l'icône facultative
`favicon.ico`, absente du site, renvoie une erreur 404 ; les ressources des pages
sont accessibles. Les tests Web et les scénarios Flutter d'affichage passent.
Le test Support attend maintenant le chargement des coordonnées et le rendu du
défilement avant son clic, afin de fonctionner avec les coordonnées publiques actives.

Les liens seront disponibles dans l'application reconstruite à partir de la version
1.0.2, y compris avant connexion et pour un compte en attente ou suspendu. La
publication du site ne met pas à jour l'ancien APK installé. La suppression prépare un email : l'utilisateur
doit l'envoyer, puis le support doit réellement traiter la demande. Il n'y a pas
d'effacement automatique ni de tableau de suivi des demandes dans cette version.

## Modèle commercial et accès à l'examen

- [ ] Faire valider le modèle vendu puis activé hors application au regard des
  règles Google Play applicables au pays et au service. Les messages d'activation
  sont désormais neutres, mais cela ne dispense pas de respecter les règles de
  paiement. Ne pas ajouter de lien ou d'instruction d'achat externe sans examen.
- [ ] Fournir à Google un compte de démonstration activé, non administrateur,
  contenant uniquement des données fictives et restant utilisable durant l'examen.
  Ne jamais mettre son mot de passe dans Git, la documentation ou des captures.
- [ ] Remplir précisément les instructions d'accès de Play Console : compte partagé
  par pharmacie, activation et fonctions protégées. Ne pas fournir le compte réel
  du propriétaire ni les données d'une pharmacie cliente.

## Identité, signature et mises à jour

Le package actuel est `com.example.pharmaflow`. Le conserver permet d'envisager une
mise à jour des installations existantes ; le renommer crée une application distincte.
Il faut décider de l'identifiant définitif avant la première publication. Aucun
renommage ni changement de projet Firebase n'est effectué par cette préparation.

Les anciens APK contrôlés avant la reconstruction avaient les codes suivants :

| APK | Version affichée | versionCode |
|---|---|---|
| ARM64 | 1.0.1 | 2002 |
| ARMv7 | 1.0.0 | 1001 |
| x86_64 | 1.0.0 | 4001 |

La source passe à `1.0.2+5000`. Les APK de test reconstruits le 16 octobre 2026
portent désormais les codes **7000 pour ARM64** et **6000 pour ARMv7**, avec le
même certificat de signature. Voir `APK_TEST.md` pour les fichiers et empreintes.
Le prochain AAB destiné à remplacer ces APK devra donc avoir un code **supérieur
à 7000** ; ne pas construire cet AAB avec le code source actuel `5000`.
Flutter ajoute des décalages de code aux APK produits avec `--split-per-abi` : si
d'autres APK sont distribués, relever leurs codes et choisir ensuite un numéro
d'AAB supérieur à **tous** les codes distribués. Ne pas revenir à `+3`.

- [ ] Sauvegarder de manière sécurisée la clé de signature et ses secrets, hors Git.
- [ ] Configurer Play App Signing avec une stratégie préservant le certificat des
  APK déjà distribués si leur mise à jour sans désinstallation est souhaitée.
  La clé d'import et la clé de signature de l'application ne sont pas interchangeables.
  Le même nom de package et un numéro plus élevé ne suffisent pas si le certificat diffère.
- [ ] Construire l'AAB signé après validation de la configuration publique :
  `flutter build appbundle --release` avec JDK 21 et des limites mémoire adaptées.
- [ ] Vérifier le package, le code de version, le certificat et les exigences API
  actuellement affichées par Play Console sur l'artefact final.
- [ ] Contrôler les alignements ELF et ZIP 16 Ko, puis tester sur un environnement
  Android 16 Ko. Une vérification de l'ancien APK ne valide pas le nouvel AAB.

L'inspection de l'ancien APK ARM64 1.0.1 montre des segments ELF alignés sur 4 Ko
dans `libbarhopper_v3.so` et `libimage_processing_util_jni.so`. Le scanner passe de
`mobile_scanner` 4.0.1 à 7.4.2 et son appel Dart est adapté. Il faut contrôler les
bibliothèques obtenues après recompilation, puis le fonctionnement réel de la caméra.
Le modèle de reconnaissance reste embarqué pour conserver le scan hors connexion.

Validation locale du 16 octobre 2026 : les ressources Android et le code Kotlin
du scanner compilent. Les bibliothèques fusionnées ARM64 et x86_64 ont toutes des
segments `PT_LOAD` alignés sur au moins 16 Ko, notamment les deux bibliothèques
précédemment incompatibles. Cela ne remplace pas l'examen de l'AAB final ni un test
sur un appareil 16 Ko. Les APK ARM64 et ARMv7 ont ensuite été reconstruits : leur
alignement ZIP a été validé avec `zipalign -c -P 16 4`, et les sept bibliothèques
ELF embarquées dans l'APK ARM64 ont un alignement `PT_LOAD` d'au moins 16 Ko.
Aucun AAB n'a encore été produit ; le test sur un appareil 16 Ko reste nécessaire.

Ne pas désinstaller une ancienne version contenant des ventes non synchronisées
pour contourner une incompatibilité de signature. Préparer d'abord une migration
et une sauvegarde chiffrée vérifiée.

## Confidentialité et fiche Play

- [ ] Déclarer les données réellement collectées dans « Sécurité des données » :
  compte, coordonnées, activité métier synchronisée et identifiants techniques
  des SDK, avec leurs finalités. Examiner aussi les SDK embarqués même peu utilisés.
- [ ] Examiner notamment Firebase Auth, Firestore, Messaging et les SDK du scanner.
  Ne pas déclarer « aucune collecte » parce que le tableau de bord ne voit pas les ventes.
- [ ] Fournir les URL publiques de confidentialité et de demande de suppression.
- [ ] Préparer titre, description, icône, captures sans données réelles, classification,
  déclaration publicitaire et coordonnées publiques cohérentes.
- [ ] Vérifier les déclarations relatives à la santé proposées par Play Console.
  Présenter l'application comme un outil de gestion, sans promesse médicale.

Les permissions de stockage global, d'appel direct et de biométrie inutilisées
sont exclues du manifeste. La caméra est facultative. Les sauvegardes Android
automatiques et le transfert système des données sont exclus ; cela ne supprime
pas d'anciennes copies. La sauvegarde manuelle chiffrée et Firebase restent disponibles.

## Recette avant diffusion

La confirmation email est intégrée aux nouveaux APK et au tableau de bord publié
le 16 octobre 2026. Les règles Firestore adaptées ne sont pas encore publiées.
Suivre `EMAIL_VERIFICATION.md` pour préparer les comptes existants avant de les
activer ; les contrôles du nouvel APK ne remplacent pas cette protection serveur.

- [ ] Inscription, mot de passe oublié, activation, suspension, reconnexion et support.
- [ ] Lien de confirmation email réellement reçu, renvoi, expiration, nouveau jeton
  et reprise des comptes existants, dont celui de l'administrateur.
- [ ] Demande de suppression avec et sans application email, sans session et après suspension.
- [ ] Vente, lots, péremptions, conversions carton/boîte/plaquette et stock insuffisant.
- [ ] Deux appareils du même compte, ventes simultanées, mode avion puis reconnexion,
  erreurs de synchronisation et prévention des doublons. Tester sur données fictives.
- [ ] PDF, partage, sauvegarde et restauration chiffrées après retrait des permissions.
- [ ] Caméra refusée, notifications refusées, petit téléphone, tablette, paysage,
  clavier affiché et texte agrandi. Le portrait n'est plus imposé par Android.
- [ ] Mise à jour depuis l'APK réellement distribué sans perte des données locales.
- [ ] Tests automatisés et rapport pré-lancement de Play Console.
- [ ] Remplir les conditions de test et d'accès à la production propres au compte
  développeur ; un test réussi ne constitue pas une approbation de publication.

Commandes locales utiles :

```text
flutter test --no-pub
node --test test/public_information_test.mjs test/admin_dashboard_test.mjs
npm --prefix admin run test:browser -- legal.spec.mjs
node scripts/check_public_information.mjs
```

Le dernier contrôle échoue volontairement tant que les coordonnées et la politique
ne sont pas validées. Les tests complets du tableau de bord et des règles Firestore
utilisent les émulateurs, selon `admin/README.md`.

Résultats locaux de cette préparation : 270 tests Flutter, 6 tests Node et 3 tests
navigateur réussis. L'analyse Flutter ne signale aucune erreur ni avertissement,
mais conserve 82 diagnostics informatifs de style/dépréciation. Les tâches Gradle
`processReleaseResources`, `compileReleaseKotlin` du scanner et
`mergeReleaseNativeLibs` réussissent. Le manifeste fusionné confirme l'absence des
cinq permissions retirées et les exclusions de sauvegarde. Les tests sur appareils
réels, l'effacement manuel complet et l'examen Google Play restent à effectuer.

## Références officielles

- [Suppression de compte et demande Web](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr)
- [Données utilisateur](https://support.google.com/googleplay/android-developer/answer/10144311?hl=fr)
- [Politique de paiement](https://support.google.com/googleplay/android-developer/answer/10281818?hl=fr)
- [Sécurité des données](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
- [Play App Signing](https://developer.android.com/studio/publish/app-signing)
- [Compatibilité des pages mémoire 16 Ko](https://developer.android.com/guide/practices/page-sizes)
- [Sauvegardes Android](https://developer.android.com/identity/data/autobackup)

Consulter à nouveau ces exigences au moment de soumettre la version.
