import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../config/auth_provider.dart';
import '../../../core/errors/user_message.dart';
import '../../../local_database/local_database.dart';
import '../../../models/models.dart';
import '../../../repositories/medicament_repository.dart';
import '../../../repositories/stock_repository.dart';

final lotsDataProvider = FutureProvider.autoDispose
    .family<(MedicamentModel?, List<ActiviteModel>), String>((ref, id) async {
      ref.watch(localChangesProvider);
      final owner = ref.watch(currentPharmacieProvider).valueOrNull?.id;
      if (owner == null) throw StateError('Connectez-vous à votre pharmacie.');
      final medicines = ref.watch(medicamentRepositoryProvider);
      final stock = ref.watch(stockRepositoryProvider);
      return (
        await medicines.getMedicamentById(owner, id),
        await stock.movements(owner, id),
      );
    });

class LotsScreen extends ConsumerStatefulWidget {
  final String id;
  const LotsScreen({super.key, required this.id});
  @override
  ConsumerState<LotsScreen> createState() => _LotsScreenState();
}

class _LotsScreenState extends ConsumerState<LotsScreen> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ref.invalidate(lotsDataProvider(widget.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock enregistré sur cet appareil.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate(MedicamentModel medicine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activer le suivi par lots ?'),
        content: const SingleChildScrollView(
          child: Text(
            'Le stock actuel sera conservé dans un lot « Stock initial », avec son prix et sa date actuels. '
            'Les futurs arrivages auront chacun leur prix et leur péremption. Les conversions seront verrouillées.\n\n'
            'Avant de continuer, mettez tous les appareils à jour et faites publier les nouvelles règles Firebase. '
            'Cette activation ne peut pas être annulée depuis l’application.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => ref.read(stockRepositoryProvider).activate(medicine));
    }
  }

  Future<void> _edit(MedicamentModel medicine, [StockLot? lot]) async {
    final entry = await showDialog<_StockEntry>(
      context: context,
      builder: (_) => _StockEntryDialog(medicine: medicine, lot: lot),
    );
    if (entry == null || !mounted) return;
    await _run(() {
      final repository = ref.read(stockRepositoryProvider);
      if (lot != null) {
        return repository.adjust(
          medicine,
          lot.id,
          entry.quantity,
          entry.reason,
        );
      }
      return repository.receive(
        medicine,
        StockLot(
          id: const Uuid().v4(),
          numero: entry.number,
          quantiteBase: entry.quantity,
          coutBase: entry.cost,
          expiration: entry.expiration,
          reception: DateTime.now(),
          fournisseur: entry.supplier,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Lots et mouvements'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Lots'),
            Tab(text: 'Mouvements'),
          ],
        ),
      ),
      body: ref
          .watch(lotsDataProvider(widget.id))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(userMessage(error)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(lotsDataProvider(widget.id)),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
            data: (data) {
              final medicine = data.$1;
              if (medicine == null) {
                return const Center(child: Text('Produit introuvable.'));
              }
              final base = medicine.unitePrix == 'flacon'
                  ? 'flacons'
                  : 'comprimés';
              return TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        medicine.nom,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('Stock physique : ${medicine.unites.affichage}'),
                      if (medicine.suiviLots)
                        Text(
                          'Vendable : ${medicine.unitesVendables.affichage}',
                        ),
                      const SizedBox(height: 12),
                      if (!medicine.suiviLots) ...[
                        const Text(
                          'Le suivi par lots est facultatif. Il permet de vendre en priorité les lots qui expirent le plus tôt et d’exclure les lots expirés.',
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _activate(medicine),
                          child: const Text('Activer le suivi par lots'),
                        ),
                      ] else ...[
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _edit(medicine),
                          icon: const Icon(Icons.add),
                          label: const Text('Réceptionner un lot'),
                        ),
                        const Text(
                          'Les dates inconnues restent vendables, en dernier. Vérifiez les emballages. Une correction change le stock physique du lot, pas une quantité vendue.',
                        ),
                        if (medicine.lots!.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Aucun lot. Enregistrez un arrivage.'),
                          ),
                        for (final lot in medicine.lots!)
                          Card(
                            child: ListTile(
                              title: Text(lot.numero),
                              subtitle: Text(
                                '${lot.quantiteBase} $base • Achat : ${lot.coutBase.toStringAsFixed(2)} FC / unité de base\n'
                                '${lot.expiration == null ? 'Péremption inconnue : à vérifier' : 'Péremption : ${DateFormat('dd/MM/yyyy').format(lot.expiration!)}'}'
                                '${lot.expiredAt(DateTime.now()) && lot.quantiteBase > 0 ? ' — EXCLU DES VENTES' : ''}'
                                '${lot.fournisseur.isEmpty ? '' : '\nFournisseur : ${lot.fournisseur}'}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Corriger le stock physique',
                                onPressed: _busy
                                    ? null
                                    : () => _edit(medicine, lot),
                                icon: const Icon(Icons.edit_note),
                              ),
                            ),
                          ),
                      ],
                      if (_busy) const LinearProgressIndicator(),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Quantités en unités de base. Les soldes avant/après sont ceux de l’appareil au moment de la saisie. Les anciennes opérations ne sont pas reconstituées.',
                      ),
                      if (data.$2.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Aucun mouvement enregistré.'),
                        ),
                      for (final movement in data.$2)
                        Card(
                          child: ListTile(
                            title: Text(movement.description),
                            subtitle: Text(
                              '${DateFormat('dd/MM/yyyy HH:mm').format(movement.date)}\n'
                              '${movement.metadata?['avant']} → ${movement.metadata?['apres']} $base'
                              '${movement.metadata?['vente_id'] == null ? '' : '\nVente : ${movement.metadata?['vente_id']}'}'
                              '${movement.metadata?['lot_id'] == null ? '' : '\nLot : ${movement.metadata?['lot_id']}'}'
                              '${(movement.metadata?['lots'] as List? ?? []).map((entry) => '\n${entry['numero']} : −${entry['quantite_base']}').join()}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
    ),
  );
}

class _StockEntry {
  final String number, supplier, reason;
  final int quantity;
  final double cost;
  final DateTime? expiration;
  _StockEntry(
    this.number,
    this.supplier,
    this.reason,
    this.quantity,
    this.cost,
    this.expiration,
  );
}

class _StockEntryDialog extends StatefulWidget {
  final MedicamentModel medicine;
  final StockLot? lot;
  const _StockEntryDialog({required this.medicine, this.lot});
  @override
  State<_StockEntryDialog> createState() => _StockEntryDialogState();
}

class _StockEntryDialogState extends State<_StockEntryDialog> {
  final _number = TextEditingController();
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  final _supplier = TextEditingController();
  final _reason = TextEditingController();
  late String _unit;
  DateTime? _expiration;
  String? _error;
  bool get _adjustment => widget.lot != null;
  @override
  void initState() {
    super.initState();
    _unit = _adjustment
        ? (widget.medicine.unitePrix == 'flacon' ? 'flacon' : 'comprimes')
        : widget.medicine.unitePrix;
    _quantity.text = widget.lot?.quantiteBase.toString() ?? '';
    _supplier.text = widget.medicine.fournisseurNom;
  }

  @override
  void dispose() {
    for (final controller in [_number, _quantity, _cost, _supplier, _reason]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final quantity = int.tryParse(_quantity.text.trim());
    final cost = double.tryParse(_cost.text.trim().replaceAll(',', '.'));
    if (quantity == null ||
        quantity < 0 ||
        quantity > 1000000000000 ||
        (_adjustment
            ? _reason.text.trim().isEmpty
            : quantity == 0 ||
                  _number.text.trim().isEmpty ||
                  _number.text.trim().length > 100 ||
                  cost == null ||
                  !cost.isFinite ||
                  cost < 0 ||
                  _expiration == null)) {
      setState(
        () => _error = _adjustment
            ? 'Indiquez une quantité entière positive ou nulle et un motif.'
            : 'Vérifiez le numéro, la quantité entière positive, le prix et la date.',
      );
      return;
    }
    final factor = widget.medicine.unites.facteur(_unit);
    Navigator.pop(
      context,
      _StockEntry(
        _number.text.trim(),
        _supplier.text.trim(),
        _reason.text.trim(),
        quantity * factor,
        (cost ?? 0) / factor,
        _expiration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      _adjustment ? 'Corriger ${widget.lot!.numero}' : 'Réceptionner un lot',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_adjustment)
            Text(
              'Stock actuel : ${widget.lot!.quantiteBase} $_unit. Saisissez le nouveau total compté, pas la différence.',
            )
          else
            TextField(
              controller: _number,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Numéro du lot'),
            ),
          if (!_adjustment)
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _unit,
              decoration: const InputDecoration(
                labelText: 'Unité réceptionnée',
              ),
              items:
                  (widget.medicine.unitePrix == 'flacon'
                          ? ['flacon']
                          : ['carton', 'boite', 'plaquette', 'comprimes'])
                      .map(
                        (unit) =>
                            DropdownMenuItem(value: unit, child: Text(unit)),
                      )
                      .toList(),
              onChanged: (unit) {
                if (unit != null) setState(() => _unit = unit);
              },
            ),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _adjustment
                  ? 'Nouveau stock physique ($_unit)'
                  : 'Quantité ($_unit)',
            ),
          ),
          if (_adjustment)
            TextField(
              controller: _reason,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Motif obligatoire',
                hintText: 'Casse, péremption, erreur de comptage…',
              ),
            )
          else ...[
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Prix d’achat (FC / $_unit)',
              ),
            ),
            TextField(
              controller: _supplier,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Fournisseur (facultatif)',
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.event),
              label: Text(
                _expiration == null
                    ? 'Date de péremption (obligatoire)'
                    : DateFormat('dd/MM/yyyy').format(_expiration!),
              ),
              onPressed: () async {
                final now = DateUtils.dateOnly(DateTime.now());
                final selected = await showDatePicker(
                  context: context,
                  initialDate:
                      _expiration ?? now.add(const Duration(days: 365)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 30),
                );
                if (selected != null && mounted) {
                  setState(() => _expiration = selected);
                }
              },
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
    ],
  );
}
