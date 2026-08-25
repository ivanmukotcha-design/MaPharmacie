# Ma Pharmacie 💊
### Gestion de stock pharmaceutique SaaS — Marché africain

> Application mobile Flutter professionnelle pour pharmacies grossistes et détaillantes.
> Optimisée Android, offline-first, multi-tenant SaaS.

---

## 📱 Fonctionnalités

| Module | Fonctionnalités |
|---|---|
| **Auth** | Email/MDP, Google Sign-In, Reset MDP |
| **Inscription** | Choix type (détaillant/grossiste), paiement frais création |
| **Dashboard** | Stats temps réel, alertes, accès rapide |
| **Stock** | CRUD médicaments, unités hiérarchiques, code-barres |
| **Ventes** | POS panier, vente gros/détail, historique |
| **Fournisseurs** | CRUD, contact direct |
| **Abonnement** | Gestion SaaS, paiement Airtel Money / M-Pesa |
| **Rapports** | Export Excel + Word (HTML) |
| **Notifications** | FCM + locales, alertes stock et expiration |
| **Hors ligne** | Sqflite + sync automatique |
| **Super Admin** | Toutes les pharmacies, tarifs, statuts |

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── constants/     # AppConstants, statuts, types
│   ├── errors/        # Exceptions métier
│   ├── utils/         # Helpers, formatters
│   └── theme/         # AppTheme, colors, typography
├── config/
│   ├── router.dart    # GoRouter — toutes les routes
│   └── auth_provider.dart  # Firebase Auth + Riverpod
├── services/
│   ├── sync_service.dart       # Sync Sqflite ↔ Firestore
│   ├── abonnement_service.dart # Logique SaaS + accès guard
│   ├── notification_service.dart # FCM + local notifications
│   └── export_service.dart     # Excel + Word (HTML)
├── models/
│   └── models.dart    # Tous les modèles de données
├── local_database/
│   └── local_database.dart  # Sqflite — toutes les tables
├── shared/
│   └── widgets/       # PfButton, PfTextField, PfBadge, etc.
└── features/
    ├── auth/          # Login, Register, Paiement inscription
    ├── dashboard/     # Stats, alertes, accès rapide
    ├── stock/         # Liste, détail, formulaire médicament
    ├── sales/         # POS vente, historique
    ├── suppliers/     # Fournisseurs CRUD
    ├── subscription/  # Abonnement SaaS
    ├── reports/       # Exports Excel/Word
    ├── support/       # Contact, FAQ
    ├── settings/      # Paramètres, déconnexion
    └── admin/         # Super Admin dashboard
```

---

## 🚀 Installation

### 1. Prérequis
```bash
flutter --version  # >= 3.0.0
dart --version     # >= 3.0.0
```

### 2. Cloner et installer
```bash
git clone https://github.com/votre-org/pharmaflow.git
cd pharmaflow
flutter pub get
```

### 3. Configurer Firebase

1. Créer un projet sur [Firebase Console](https://console.firebase.google.com)
2. Ajouter une app Android (package: `com.pharmaflow.app`)
3. Télécharger `google-services.json` → `android/app/`
4. Activer les services :
   - Firebase Authentication (Email/MDP + Google)
   - Cloud Firestore
   - Firebase Storage
   - Firebase Cloud Messaging

```bash
# Installer FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurer
flutterfire configure
```

### 4. Déployer les règles Firestore
```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

### 5. Initialiser les tarifs (Firestore)
Créer le document `config/tarifs` :
```json
{
  "frais_creation_compte": 5000,
  "abonnement_mensuel_detaillant": 10000,
  "abonnement_mensuel_grossiste": 25000,
  "updated_at": "2024-01-01T00:00:00Z"
}
```

### 6. Créer le Super Admin (Firestore)
Créer le document `admins/{uid_admin}` :
```json
{
  "email": "admin@pharmaflow.app",
  "created_at": "..."
}
```

### 7. Lancer l'application
```bash
flutter run --release
```

---

## 🔑 Variables d'environnement

Créer `lib/config/env.dart` :
```dart
class Env {
  static const supportEmail = 'support@pharmaflow.app';
  static const supportWhatsapp = '+243810000000';
  static const airtelMoneyNumero = '+243810000000';
  static const mpesaNumero = '+243970000000';
  static const nomBeneficiaire = 'PHARMAFLOW SAS';
}
```

---

## 💾 Structure Firestore

```
firestore/
├── config/
│   └── tarifs          # Frais et abonnements
├── admins/
│   └── {uid}           # Super admins
├── pharmacies/
│   └── {pharmacie_id}  # Une entrée par pharmacie (uid Firebase)
│       ├── medicaments/
│       ├── ventes/
│       ├── fournisseurs/
│       ├── activites/
│       └── notifications/
├── abonnements/        # Collection globale
└── paiements/          # Collection globale
```

---

## 📊 Modèles de données clés

### PharmacieModel
```dart
id, code (PHR-0001), nom, email, telephone, adresse,
ville, pays, typePharmacie, statut, proprietaireNom, createdAt
```

### MedicamentModel
```dart
id, pharmacieId, nom, categorie, description,
prixGrossiste, prixDetail, fournisseurId, imageUrl,
dateExpiration, codeBarres, seuilAlerte, unites (UnitesStock)
```

### UnitesStock (conversions automatiques)
```dart
cartons, boites, plaquettes, comprimes, flacons
cartonsParBoite = 20, boitesParPlaquette = 10, plaquettesParComprime = 10
```

---

## 🔐 Logique SaaS

| Statut | Lire | Écrire | Vendre |
|--------|------|--------|--------|
| `actif` | ✅ | ✅ | ✅ |
| `expire` | ✅ | ❌ | ❌ |
| `suspendu` | ❌ | ❌ | ❌ |
| `attente_paiement` | ❌ | ❌ | ❌ |

---

## 📱 Screens

1. **Login** — Email/MDP + Google
2. **Register** — Stepper 3 étapes (pharmacie, contact, compte)
3. **Paiement inscription** — Airtel Money / M-Pesa
4. **Dashboard** — Stats, alertes, accès rapide
5. **Stock** — Liste filtrée, recherche, scanner CB
6. **Médicament détail** — Stock par unité, tarifs, expiration
7. **Médicament formulaire** — Ajout/modif avec conversion unités
8. **Ventes (POS)** — Panier, type vente, finalisation
9. **Historique ventes** — Filtres dates, résumé
10. **Fournisseurs** — Liste, ajout, contact
11. **Abonnement** — Statut, renouvellement, historique paiements
12. **Rapports** — 6 types de rapports, export Excel/Word
13. **Support** — Email, WhatsApp, FAQ
14. **Paramètres** — Thème, compte, déconnexion
15. **Admin dashboard** — Toutes pharmacies, stats globales
16. **Admin tarifs** — Modifier frais et abonnements

---

## 🎨 Design System

| Couleur | Utilisation |
|---------|-------------|
| `#0B6E4F` | Primary (vert médical) |
| `#1A9E73` | Primary Light |
| `#1B72BE` | Secondary (bleu médical) |
| `#1A9E73` | Success / Stock correct |
| `#E88C1A` | Warning / Stock faible |
| `#D03030` | Danger / Rupture |

**Police :** Poppins (Regular 400, Medium 500, SemiBold 600, Bold 700)

---

## 📦 Packages principaux

```yaml
firebase_core, firebase_auth, cloud_firestore,
firebase_storage, firebase_messaging,
flutter_riverpod, go_router,
sqflite, connectivity_plus,
fl_chart, animations, shimmer,
mobile_scanner, image_picker,
excel, share_plus, path_provider,
flutter_local_notifications
```

---

## 🧪 Tests

```bash
flutter test
flutter test integration_test/
```

---

## 📬 Support

- **Email :** support@pharmaflow.app
- **WhatsApp :** +243 81 000 0000

---

*Ma Pharmacie v1.0.0 — Conçu pour le marché africain 🌍*
