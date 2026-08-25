# Implementation Plan - Custom Splash Screen, Google Icon and App Icon Update

This plan describes the addition of a custom Splash Screen, the update of the Google Sign-In icon, and changing the application's launcher icon.

## Proposed Changes

### Assets & Dependencies

#### [MODIFY] [pubspec.yaml](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/pubspec.yaml)
- Add `flutter_launcher_icons: ^0.13.1` to `dev_dependencies`.
- Configure `flutter_launcher_icons` to use `assets/images/3.jpg` as the source for the app icon.

### Authentication & UI

#### [NEW] [splash_screen.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/features/auth/presentation/splash_screen.dart)
- Create a new widget that displays `assets/images/1.jpg` in the center.
- Add the text "Accéder à votre espace pharmaceutique" below the image using `AppTextStyles`.
- Use a `Timer` or `Future.delayed` to wait for 2 seconds before navigating.

#### [MODIFY] [login_screen.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/features/auth/presentation/login_screen.dart)
- In `_GoogleButton`, replace the red "G" container with an `Image.asset('assets/images/5.png')`.

### Navigation

#### [MODIFY] [router.dart](file:///C:/Users/ivan/Desktop/FLUTTER PROJECTS/pharmaflow/lib/config/router.dart)
- Add a route for `/splash`.
- Set `initialLocation: '/splash'`.
- Adjust the `redirect` logic: if the current location is `/splash`, don't redirect yet (let the splash screen handle its timer).

## Verification Plan

### Automated Steps
- Run `flutter pub get`.
- Run `flutter pub run flutter_launcher_icons` to generate the new app icons.

### Manual Verification
- **Splash Screen**: Launch the app and confirm the image and text appear correctly.
- **Redirection**: Confirm it goes to Dashboard (if logged in) or Login (if logged out) after the splash.
- **Google Icon**: Verify the new icon is visible on the Login screen.
- **App Icon**: Verify the icon on the device's home screen has changed to the image from `3.jpg`.
