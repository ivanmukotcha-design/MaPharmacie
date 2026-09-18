import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/auth_provider.dart';

final repositoryAccessProvider = Provider<RepositoryAccess>(
  RepositoryAccess.forRef,
);

class RepositoryAccess {
  final void Function(String pharmacieId, bool write) check;

  RepositoryAccess(this.check);

  factory RepositoryAccess.forRef(Ref ref) =>
      RepositoryAccess((pharmacieId, write) {
        final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
        final user = ref.read(currentUserProvider);
        if (user?.uid != pharmacieId ||
            pharmacie?.id != pharmacieId ||
            pharmacie == null ||
            !ref.read(pharmacieAuthorizedProvider)) {
          throw StateError('Accès refusé pour cette pharmacie.');
        }
      });

  void read(String pharmacieId) => check(pharmacieId, false);
  void write(String pharmacieId) => check(pharmacieId, true);
}
