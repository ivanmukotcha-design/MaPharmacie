# Walkthrough - Login with Username and Email Registration

I have updated the authentication flow to support **Username** as the primary login identifier while still requiring an **Email** during registration.

## Changes Made

### 1. Data Model
- **`PharmacieModel`**: Added a `username` field to store and retrieve the unique identifier for each pharmacy.

### 2. Authentication Logic
- **`AuthService`**:
    - Added `loginWithUsername`: This method first looks up the associated email in Firestore using the username and then performs a standard Firebase email/password login.
    - Updated `creerPharmacie` to save the `username` field in the Firestore document.

### 3. User Interface
- **`RegisterScreen`**: Added a new "Nom d'utilisateur" field in the final step of the registration process.
- **`LoginScreen`**:
    - Replaced the "Email" field with a "Nom d'utilisateur" field.
    - Updated the "Continuer avec Google" button to use the high-quality logo from `assets/images/5.png` (from previous task).

## Verification
- Registration now saves both `email` and `username`.
- Login successfully resolves the username to an email and authenticates.
- Google Sign-In remains functional.

render_diffs(file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/models/models.dart)
render_diffs(file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/config/auth_provider.dart)
render_diffs(file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/features/auth/presentation/register_screen.dart)
render_diffs(file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/features/auth/presentation/login_screen.dart)
