# APK de test — 16 octobre 2026

## Fichiers disponibles

Version affichée : **1.0.2**. Package conservé : `com.example.pharmaflow`.
Android minimal déclaré : API 24 (Android 7.0). API cible : 36.

| Architecture | Fichier depuis la racine du projet | Taille exacte | versionCode |
|---|---|---|---|
| ARM64, à essayer en premier sur un téléphone récent | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 32 624 294 octets | 7000 |
| ARMv7, pour un système Android ARM 32 bits | `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` | 29 214 996 octets | 6000 |

L'ancien APK x86_64 présent dans le répertoire n'a pas été reconstruit et ne doit
pas être distribué comme cette nouvelle version. Aucun AAB ni publication Google
Play n'est inclus. Les APK se trouvent sur le PC, pas sur une URL publique.

## Installation et premier parcours

1. Copier l'APK adapté sur le nouveau téléphone, puis l'ouvrir depuis le gestionnaire
   de fichiers. Autoriser temporairement cette source à installer une application
   si Android le demande. Ne pas désactiver globalement les protections du téléphone.
2. Vérifier que l'application installée affiche la version 1.0.2 dans les informations
   de l'application Android. Utiliser uniquement une pharmacie et des produits fictifs.
3. Créer un compte avec une adresse email accessible et un mot de passe propre à
   Ma Pharmacie, différent de celui de la messagerie.
4. Ouvrir le lien reçu, vérifier les indésirables si nécessaire, puis revenir dans
   l'application et appuyer sur **J’ai confirmé mon email**.
5. Compléter le profil. Le compte doit attendre une activation administrative.
6. Sur `https://mapharmacie-d56c2.web.app`, se connecter avec le compte administrateur,
   confirmer aussi son email si demandé, puis activer la pharmacie de test.
7. Revenir dans l'application et actualiser l'accès ; si nécessaire, se reconnecter.

Pour un compte existant, se connecter sans recréer la pharmacie. La confirmation
email reste nécessaire si elle n'a jamais été faite. Sur un ancien téléphone,
ne pas désinstaller pour résoudre une erreur de mise à jour : sauvegarder et
synchroniser les données avant toute opération risquant d'effacer le stockage.

Tester ensuite : ajout de produits et unités, vente normale et stock insuffisant,
retour Android, rapport PDF, scan caméra, permissions refusées, texte agrandi,
paysage, mode avion puis synchronisation. Avec deux appareils du même compte,
vérifier les modifications et ventes simultanées sur des données fictives.

## Ce qui est publié ou reste à faire

- Le tableau de bord avec confirmation email est publié. `index.html` et `app.mjs`
  servis ont été comparés aux sources locales après déploiement.
- Les nouvelles règles exigeant `email_verified` ne sont **pas** publiées pour
  éviter de bloquer les comptes existants non préparés. Suivre `EMAIL_VERIFICATION.md`
  avant leur activation. Le nouveau client bloque les emails non confirmés, mais
  cela ne valide pas encore l'application de cette exigence côté serveur.
- Aucun compte réel n'a été marqué confirmé, aucune donnée client n'a été effacée.
- La réception réelle du mail, l'installation et le fonctionnement sur le nouveau
  téléphone restent à vérifier par le testeur.

## Contrôles effectués

- 280 tests Flutter et 6 tests Node relancés avec succès avant compilation.
- Compilation release terminée avec succès. Le journal contient un échec du daemon
  Kotlin lié aux caches entre les lecteurs C: et E:, suivi de la réussite du build ;
  ce diagnostic de compilation n'est pas masqué.
- Signature des deux APK vérifiée ; certificat identique à l'ancienne release.
- Alignement ZIP des deux APK vérifié avec `zipalign -c -P 16 4`.
- Les sept bibliothèques ELF ARM64 embarquées ont des segments `PT_LOAD` alignés
  sur au moins 16 Ko. Cela ne remplace pas un test réel sur un appareil 16 Ko.
- Le fichier public `legal.json` embarqué dans l'APK ARM64 correspond à la source.

Journaux locaux : `build/apk-test-validation.log`, `build/apk-test-release-build.log`
et `build/apk-test-hosting-deploy.log`.

Empreinte SHA-256 du certificat de signature :
`1e4c7641a785f1adfd784d9bf165eb827fbdb637a98b7c1d5f21de2c5e316c96`.

Empreintes SHA-256 des fichiers :

- ARM64 : `F6A1E59D56D1E2EF09D7D71B8A707FAE0813565EA0B739EC0FA8BC5C8C549E3E`
- ARMv7 : `CA21CAD9D300BD700A6BEEE7DCF60D8D7C9CEA15CB630487E33883723D70EA0E`

Pour une future mise à jour Google Play remplaçant ces APK, utiliser un
`versionCode` supérieur à **7000** et préserver la compatibilité de signature.
