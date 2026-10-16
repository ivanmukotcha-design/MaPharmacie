import '../models/models.dart';

String? sessionRedirect({
  required String location,
  required bool loading,
  required bool hasError,
  required String? userId,
  required bool emailVerified,
  required PharmacieModel? pharmacie,
}) {
  if (['/confidentialite', '/suppression-compte'].contains(location)) {
    return null;
  }
  if (userId != null && !emailVerified) {
    return ['/verifier-email', '/support'].contains(location)
        ? null
        : '/verifier-email';
  }
  if (loading) return location == '/splash' ? null : '/splash';
  if (hasError) return location == '/acces' ? null : '/acces';
  if (userId == null) {
    return ['/login', '/register'].contains(location) ? null : '/login';
  }
  if (pharmacie == null)
    return location == '/configurer' ? null : '/configurer';
  if (pharmacie.id != userId) return location == '/acces' ? null : '/acces';
  if (!pharmacie.canWriteData) {
    final allowed = [
      '/acces',
      '/support',
      if (pharmacie.canReadData) '/sauvegardes',
    ];
    return allowed.contains(location) ? null : '/acces';
  }
  if ([
        '/login',
        '/verifier-email',
        '/configurer',
        '/register',
        '/splash',
        '/acces',
        '/abonnement',
      ].contains(location) ||
      location.startsWith('/admin'))
    return '/dashboard';
  return null;
}
