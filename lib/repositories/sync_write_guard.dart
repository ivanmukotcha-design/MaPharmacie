import 'package:sqflite/sqflite.dart';
import '../local_database/local_database.dart';
import '../services/sync_operation.dart';

Future<void> ensureNoSyncIssue(
  DatabaseExecutor database,
  String owner,
  Set<String> references,
) async {
  final pending = await LocalDatabase.getPendingSync(owner, executor: database);
  final blocked = <String>{};
  for (final row in pending) {
    final operation = SyncOperation(row);
    if (row['last_error'] != null || operation.overlaps(blocked)) {
      blocked.addAll(operation.affected);
    }
  }
  if (blocked.contains('*') || blocked.intersection(references).isNotEmpty) {
    throw StateError(
      'Une opération concernant ce produit ou fournisseur nécessite une vérification. '
      'Ouvrez Paramètres → Suivi de synchronisation avant de continuer.',
    );
  }
}
