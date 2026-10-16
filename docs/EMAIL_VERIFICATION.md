# Confirmation des adresses email

## Fonctionnement

Le mot de passe demandé est celui du compte **Ma Pharmacie**, jamais celui de
Gmail ou d'une autre messagerie. Firebase Authentication contrôle le couple
email/mot de passe. Un lien de confirmation vérifie ensuite que l'utilisateur
peut accéder à la boîte mail. Cela ne prouve pas son identité civile ni son
habilitation à représenter une pharmacie.

1. Créer le compte avec une adresse accessible et un mot de passe propre à l'application.
2. Ouvrir le lien reçu par email, éventuellement depuis un autre appareil.
3. Revenir dans l'application et appuyer sur **J’ai confirmé mon email**.
4. Compléter le profil de la pharmacie, puis attendre son activation administrative.

L'écran propose un renvoi du lien avec un délai minimal d'une minute. Les limites
supplémentaires de Firebase continuent de s'appliquer. Un échec d'envoi n'efface
pas le compte : réessayer sans le recréer. Vérifier aussi les courriers indésirables.
Si le lien est expiré, en demander un nouveau. Une adresse mal saisie peut être
abandonnée via **Se déconnecter / autre adresse**, puis une nouvelle inscription ;
ne pas supprimer un ancien compte contenant des données pour corriger son adresse.
Pour un compte existant, faire vérifier la situation par le support.

La confirmation concerne le compte commun. Sur les appareils déjà connectés,
utiliser le bouton de vérification ou se reconnecter pour actualiser leur session.
L'application recharge l'utilisateur et force le renouvellement du jeton Firebase
avant de poursuivre. Un simple clic sur « J’ai confirmé » ne suffit pas.

## Contrôles

- Le routeur bloque les écrans métier tant que l'email n'est pas confirmé.
- Aucun profil Firestore n'est chargé ni créé par la nouvelle application avant
  cette confirmation ; les contrôles des repositories et de la synchronisation
  refusent également les opérations métier.
- Les pages publiques de confidentialité, de demande de suppression et le support
  restent accessibles. Un utilisateur non confirmé peut se déconnecter.
- Les nouvelles règles Firestore exigent la propriété `email_verified: true` du
  **jeton signé par Firebase**, et non un champ que le client pourrait écrire.
  Elles protègent aussi l'annuaire et le rôle administrateur.
- La confirmation ne remplace ni l'activation commerciale, ni le rôle administrateur,
  ni les contrôles d'isolation entre pharmacies. Les statuts existants sont conservés.
- Le tableau de bord dispose aussi d'un écran d'envoi et de contrôle du lien avant
  la lecture du rôle administrateur. Confirmer un email n'accorde pas ce rôle.

## Mise en service progressive

Le tableau de bord avec confirmation email a été publié le 16 octobre 2026 sur
`https://mapharmacie-d56c2.web.app`. Les fichiers `index.html` et `app.mjs` servis
ont été comparés aux sources locales après publication. Le site public et la
politique restent en ligne. **Les règles exigeant `email_verified` ne sont pas
encore publiées** : préparer les comptes existants avant leur activation.
Les APK déjà installés ne sont pas mis à jour automatiquement par ce déploiement.

1. Vérifier le fournisseur Email/Password dans Firebase Authentication, les modèles
   d'email, le nom d'application présenté et la délivrabilité avec une adresse de test.
   Le lien utilise le gestionnaire d'action Firebase par défaut ; aucun serveur SMTP
   personnel ni mot de passe de messagerie n'est demandé.
2. Tester sur les émulateurs puis sur un compte réel de démonstration : bon/mauvais
   mot de passe, adresse non confirmée, lien expiré, renvoi, absence de réseau,
   profil en attente, compte suspendu et plusieurs appareils.
3. Publier d'abord le tableau de bord mis à jour, puis confirmer réellement l'email
   du propriétaire depuis sa messagerie. Vérifier que son rôle fonctionne toujours.
   Ne pas marquer arbitrairement un compte confirmé depuis la console pour contourner
   cette étape.
4. Préparer et distribuer l'application mise à jour. Prévenir les propriétaires des
   comptes existants : même un compte actif devra confirmer son email s'il ne l'a
   jamais fait. Ne supprimer ni profil, ni compte, ni ventes locales non synchronisées.
5. Seulement après cette préparation, publier `firestore.rules` et contrôler les
   refus/autorisation sur des comptes de test. Les anciens jetons non confirmés
   seront refusés jusqu'à leur renouvellement, même si le lien a déjà été ouvert.

Une ancienne application hors ligne peut encore afficher ses copies locales.
Les règles protègent les accès serveur ; elles n'effacent pas à distance les données
déjà enregistrées sur un appareil. Cette fonctionnalité n'est pas une garantie de
révocation immédiate hors connexion.

## Tests locaux

```text
flutter test --no-pub test/email_verification_test.dart test/auth_signup_test.dart test/access_policy_test.dart test/router_refresh_test.dart
firebase emulators:exec --only auth,firestore --project demo-pharmaflow-tests "node --test test/firestore_rules.test.cjs && npm --prefix admin run test:browser"
```

Les tests de règles et de navigateur refusent de fonctionner sans les adresses
exactes des émulateurs locaux. Ils n'envoient pas de véritables emails et ne
modifient aucun compte réel. La réception dans une vraie messagerie reste à tester.

Validation locale du 16 octobre 2026 : 280 tests Flutter, 18 tests Firebase
émulés et 8 tests navigateur réussis. Les tests couvrent notamment un mot de
passe incorrect, une adresse inconnue, un ancien jeton non confirmé, le renvoi
du lien et la confirmation par un code d'action de l'émulateur. L'analyse ne
signale aucune erreur ni avertissement ; 81 diagnostics informatifs de style
et dépréciation subsistent. Les APK release ARM64 et ARMv7 1.0.2 ont ensuite
été construits et contrôlés : voir `APK_TEST.md`. Les 280 tests Flutter ont été
relancés avec succès avant cette compilation. La réception d'un véritable email
et le parcours sur téléphone restent à tester ; les règles renforcées restent
non publiées.

Références : [gestion des utilisateurs Flutter/Firebase](https://firebase.google.com/docs/auth/flutter/manage-users),
[sessions et événements d'authentification](https://firebase.google.com/docs/auth/flutter/start),
[authentification dans les règles](https://firebase.google.com/docs/rules/rules-and-auth).
