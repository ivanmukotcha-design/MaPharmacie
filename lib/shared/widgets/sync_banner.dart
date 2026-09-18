import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/auth_provider.dart';
import '../../local_database/local_database.dart';
import '../../services/sync_service.dart';

final pendingSyncProvider = FutureProvider<int>((ref) async {
  ref.watch(localChangesProvider);
  final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
  if (pharmacie == null) return 0;
  return (await LocalDatabase.getPendingSync(pharmacie.id)).length;
});

class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).valueOrNull;
    final pending = ref.watch(pendingSyncProvider).valueOrNull ?? 0;
    final message =
        status?.error ??
        (status?.running == true
            ? 'Synchronisation en cours…'
            : pending > 0
            ? '$pending opération(s) enregistrée(s) sur cet appareil, en attente de synchronisation.'
            : null);
    if (message == null) return const SizedBox.shrink();
    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}
