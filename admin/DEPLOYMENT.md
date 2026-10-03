# Publication du 3 octobre 2026

## Services publiés

- Projet Firebase : `mapharmacie-d56c2`.
- Tableau de bord : https://mapharmacie-d56c2.web.app.
- Première publication Hosting effectuée sur le site par défaut, auparavant vide.
- Dix index Firestore vérifiés à l'état `READY`, dont l'historique `account_events`.
- Règles publiées le 3 octobre 2026 à 15:39:29 UTC et comparées au fichier local.
- Référence publiée : `projects/mapharmacie-d56c2/rulesets/daf465e2-b6b7-42c0-b8e6-8f4fe122572f`.
- Référence précédente : `projects/mapharmacie-d56c2/rulesets/e37870e7-0007-4578-831f-537c328989b5`.

La référence précédente sert à la traçabilité, pas à un retour automatique :
restaurer des règles anciennes pourrait annuler la protection liée aux statuts.
Le rôle du compte personnel administrateur a été vérifié. Aucun compte client
n'a été activé, suspendu ou supprimé lors de cette publication.

## APK disponible

- Fichier : `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
- Version : `1.0.1+2`, code Android ARM64 `2002`.
- Application : `com.example.pharmaflow`, Android API minimale `24`, cible `36`.
- Taille : `31 631 833` octets, soit environ 31,6 Mo.
- SHA-256 : `28D331B7A4751F78B5D7637A43BD1480F423411E84BE6744371542022FECC071`.
- Certificat SHA-256 conservé : `1e4c7641a785f1adfd784d9bf165eb827fbdb637a98b7c1d5f21de2c5e316c96`.
- Signature APK v2 vérifiée ; présence du statut d'accès et de l'annuaire client
  confirmée dans la bibliothèque compilée.

**Seul cet APK ARM64 est à jour.** Les fichiers `armeabi-v7a` et `x86_64` encore
présents dans le dossier sont les anciennes versions du 2 octobre et ne doivent
pas être distribués comme cette mise à jour.

La compilation a réussi avec Java 21 pour Gradle, un worker et une mémoire
réduite, en environ 13 minutes. La commande reproductible figure dans
[le guide administrateur](README.md#compilation-android-sur-un-pc-windows-à-mémoire-limitée).

## Contrôles effectués

- Tests précédant la publication : 264 tests Flutter, 17 tests Firebase Emulator,
  quatre scénarios navigateur et deux tests JavaScript réussis.
- Page de connexion publiée vérifiée avec Edge aux largeurs 320 et 1280 pixels,
  sans débordement horizontal ni violation de la politique CSP.
- Configuration Hosting reliée au bon projet ; espace client masqué sans connexion.
- Accès Firestore anonyme refusé (`403 PERMISSION_DENIED`) pour l'annuaire,
  le rôle administrateur et le profil pharmacie contrôlés.
- Aucun mot de passe demandé ni utilisé ; connexion réelle de l'administrateur
  et installation sur téléphone non effectuées par ces contrôles.

## Tests à faire avec le propriétaire

1. Synchroniser et sauvegarder l'application existante avant la mise à jour.
2. Installer l'APK ARM64 sur un appareil compatible, sans désinstaller la version
   précédente. En cas d'erreur de signature, conserver l'application et ses données.
3. Ouvrir l'application en ligne : les anciens profils sans statut restent actifs
   et leurs coordonnées sont alors ajoutées à l'annuaire.
4. Se connecter au tableau de bord avec le compte personnel administrateur.
5. Avec un compte de pharmacie fictif distinct, tester inscription en attente,
   activation, utilisation sur deux appareils, suspension, sauvegarde locale
   puis réactivation. Vérifier aussi le comportement hors connexion.

Les nouvelles inscriptions depuis un ancien APK sont désormais refusées par
les règles. Une suspension n'efface pas les données et n'est pas instantanée
sur un appareil hors connexion. Le compte administrateur ne doit jamais être
partagé avec un client ou un employé.
