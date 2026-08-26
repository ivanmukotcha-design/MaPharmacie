# Implementation Plan - Registration with Email and Username

This plan describes the changes required to allow users to register with both an email and a username, and log in using either their username or Google.

## User Review Required

> [!IMPORTANT]
> To support login by **username**, we will store a mapping in Firestore. Since Firebase Auth does not natively support custom usernames as primary identifiers, we will use a "hidden email" pattern or search for the user's email in Firestore based on their username.
> I will add a `username` field to the `PharmacieModel`.

## Proposed Changes

### Data Models

#### [MODIFY] [models.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/models/models.dart)
- Add `username` field to `PharmacieModel`.

### Authentication Logic

#### [MODIFY] [auth_provider.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/config/auth_provider.dart)
- Update `AuthService.loginWithUsername` (new method):
    1. Search Firestore for a pharmacy where `username == input`.
    2. Get the associated `email`.
    3. Call `signInWithEmailAndPassword` using that email.
- Update `AuthService.creerPharmacie`: Accept and store the `username`.

### User Interface

#### [MODIFY] [register_screen.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/features/auth/presentation/register_screen.dart)
- Add a "Nom d'utilisateur" field in Step 3 (Account identifiers), alongside Email and Password.
- Ensure the username is unique (optional validation) or just pass it to the creation method.

#### [MODIFY] [login_screen.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/features/auth/presentation/login_screen.dart)
- Change "Email" field label to "Nom d'utilisateur".
- Update the login logic to call the new `loginWithUsername` method.

## Verification Plan

### Manual Verification
- **Registration**: Create a new account providing both an email and a unique username.
- **Login**: Try to log in using the newly created username and password. Verify success.
- **Google Login**: Ensure Google login still works correctly with the new icon.
