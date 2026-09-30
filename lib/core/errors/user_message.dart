import 'package:firebase_core/firebase_core.dart';

String userMessage(
  Object error, {
  String fallback =
      'Impossible de terminer cette opération. Veuillez réessayer.',
}) {
  if (error is StateError) return error.message;
  if (error is FormatException) return error.message;
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' =>
        'Accès refusé. Vérifiez votre connexion au compte de la pharmacie.',
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
        'Connexion indisponible. Vos opérations restent sur cet appareil. Réessayez avec Internet.',
      _ => fallback,
    };
  }
  return fallback;
}
