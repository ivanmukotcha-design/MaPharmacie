import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/errors/user_message.dart';
import '../../local_database/local_database.dart';
import '../../services/sync_operation.dart';
import '../../services/sync_service.dart';

final syncOperationsProvider = FutureProvider.autoDispose<List<SyncOperation>>((
  ref,
) {
  ref.watch(localChangesProvider);
  return ref.watch(syncServiceProvider).pendingOperations();
});

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = userMessage(error));
    } finally {
      if (mounted) {
        ref.invalidate(syncOperationsProvider);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reconcile(SyncOperation operation) async {
    final service = ref.read(syncServiceProvider);
    final preview = await service.previewSaleReconciliation(operation.id);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Vérifier cette vente'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Vente du ${DateFormat('dd/MM/yyyy HH:mm').format(preview.sale.date)}',
              ),
              Text('Total : ${preview.sale.totalTTC.toStringAsFixed(0)} FC'),
              const SizedBox(height: 12),
              Text(
                preview.alreadySent
                    ? 'Cette vente est déjà sur le serveur. Seul son état local sera mis à jour, sans nouvelle déduction de stock.'
                    : 'Confirmez uniquement si cette vente a réellement eu lieu et n’a pas été saisie séparément sur un autre appareil. '
                          'Ses quantités seront déduites du stock actuel du serveur, sans modifier les prix historiques.',
              ),
              for (final stock in preview.stocks) ...[
                const Divider(),
                Text(
                  stock.nom,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Stock serveur : ${stock.unites.affichage}'),
                for (final line in preview.sale.items.where(
                  (line) => line.medicamentId == stock.id,
                ))
                  Text(
                    'Vendu : ${line.quantite} ${line.unite}\n'
                    'Après rapprochement : ${stock.unites.deduire(line.quantite, line.unite).affichage}',
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await service.reconcileSale(preview);
    if (mounted) {
      setState(
        () => _message =
            'Vente rapprochée. Vérifiez les éventuelles opérations restantes.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final operations = ref.watch(syncOperationsProvider);
    final running = ref.watch(syncStatusProvider).valueOrNull?.running == true;
    final disabled = _busy || running;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de synchronisation')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Vos opérations restent conservées sur cet appareil. '
              'Ne désinstallez pas l’application tant que la liste n’est pas vide. '
              'Les opérations indépendantes peuvent continuer à se synchroniser.',
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_message!),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: disabled
                  ? null
                  : () => _run(() => ref.read(syncServiceProvider).sync()),
              icon: const Icon(Icons.sync),
              label: const Text('Réessayer la synchronisation'),
            ),
          ),
          if (disabled) const LinearProgressIndicator(),
          Expanded(
            child: operations.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text(userMessage(error))),
              data: (entries) => entries.isEmpty
                  ? const Center(child: Text('Aucune opération en attente.'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final operation = entries[index];
                        final sale = operation.kind == 'sale';
                        final name = operation.kind == 'legacy'
                            ? 'Ancienne opération'
                            : sale
                            ? 'Vente ${operation.documentId}'
                            : '${operation.document['nom'] ?? operation.documentId}';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  operation.error ??
                                      'En attente de synchronisation ou d’une opération précédente.',
                                ),
                                if (sale)
                                  TextButton(
                                    onPressed: disabled
                                        ? null
                                        : () =>
                                              _run(() => _reconcile(operation)),
                                    child: const Text(
                                      'Vérifier et rapprocher la vente',
                                    ),
                                  ),
                                if (!sale && operation.error != null)
                                  const Text(
                                    'Pour cette modification de fiche, créez une sauvegarde puis contactez le support. '
                                    'Aucun écrasement automatique du stock n’est proposé.',
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
