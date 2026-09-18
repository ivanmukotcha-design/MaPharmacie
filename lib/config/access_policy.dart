import '../models/models.dart';

String? sessionRedirect({
  required String location,
  required bool loading,
  required bool hasError,
  required String? userId,
  required PharmacieModel? pharmacie,
}) {
  if (loading) return location == '/splash' ? null : '/splash';
  if (hasError) return location == '/acces' ? null : '/acces';
  if (userId == null) {
    return ['/login', '/register'].contains(location) ? null : '/login';
  }
  if (pharmacie == null)
    return location == '/configurer' ? null : '/configurer';
  if (pharmacie.id != userId) return location == '/acces' ? null : '/acces';
  if ([
        '/login',
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
