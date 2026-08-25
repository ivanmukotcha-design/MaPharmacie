import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../../../core/constants/app_constants.dart';

final allPharmaciesProvider = StreamProvider<List<PharmacieModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(AppConstants.colPharmacies)
      .orderBy('created_at', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => PharmacieModel.fromMap(d.data(), d.id)).toList());
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmaciesAsync = ref.watch(allPharmaciesProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Super Admin'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        actions: const [],
      ),
      body: pharmaciesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (pharmacies) {
          final actives = pharmacies.where((p) => p.statut == PharmacieStatut.actif).length;
          final expirees = pharmacies.where((p) => p.statut == PharmacieStatut.expire).length;
          final suspendues = pharmacies.where((p) => p.statut == PharmacieStatut.suspendu).length;
          final attente = pharmacies.where((p) => p.statut == PharmacieStatut.attentePaiement).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Stats globales
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _adminStat('Total pharmacies', '${pharmacies.length}', Icons.local_pharmacy_rounded, AppColors.primary),
                  _adminStat('Actives', '$actives', Icons.check_circle_outline, AppColors.success),
                  _adminStat('Expirées', '$expirees', Icons.warning_amber_outlined, AppColors.warning),
                  _adminStat('Suspendues', '$suspendues', Icons.block_outlined, AppColors.danger),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Pharmacies (${pharmacies.length})', style: AppTextStyles.h4),
                  TextButton(
                    onPressed: () => context.push('/admin/pharmacies'),
                    child: const Text('Voir tout'),
                  ),
                ],
              ),

              ...pharmacies.take(10).map((p) => _PharmacieAdminRow(pharmacie: p, ref: ref)),
            ],
          );
        },
      ),
    );
  }

  Widget _adminStat(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AppTextStyles.h3.copyWith(color: color)),
              Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PharmacieAdminRow extends StatelessWidget {
  final PharmacieModel pharmacie;
  final WidgetRef ref;
  const _PharmacieAdminRow({required this.pharmacie, required this.ref});

  @override
  Widget build(BuildContext context) {
    Color statutColor;
    switch (pharmacie.statut) {
      case PharmacieStatut.actif: statutColor = AppColors.success; break;
      case PharmacieStatut.expire: statutColor = AppColors.warning; break;
      case PharmacieStatut.suspendu: statutColor = AppColors.danger; break;
      default: statutColor = AppColors.info; break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                pharmacie.nom[0].toUpperCase(),
                style: AppTextStyles.h4.copyWith(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pharmacie.nom, style: AppTextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Text(pharmacie.code, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    Text('•', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    Text(
                      pharmacie.typePharmacie == 'grossiste' ? 'Grossiste' : 'Détaillant',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statutColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statutLabel(pharmacie.statut),
                  style: AppTextStyles.caption.copyWith(color: statutColor, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16, color: AppColors.textMuted),
                onSelected: (action) => _handleAction(context, action, pharmacie),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'activer', child: Text('Activer')),
                  const PopupMenuItem(value: 'suspendre', child: Text('Suspendre')),
                  const PopupMenuItem(value: 'supprimer', child: Text('Supprimer', style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statutLabel(String statut) {
    switch (statut) {
      case PharmacieStatut.actif: return 'Actif';
      case PharmacieStatut.expire: return 'Expiré';
      case PharmacieStatut.suspendu: return 'Suspendu';
      default: return 'En attente';
    }
  }

  void _handleAction(BuildContext context, String action, PharmacieModel pharmacie) async {
    final firestore = FirebaseFirestore.instance;
    switch (action) {
      case 'activer':
        await firestore.collection(AppConstants.colPharmacies).doc(pharmacie.id).update({'statut': PharmacieStatut.actif});
        break;
      case 'suspendre':
        await firestore.collection(AppConstants.colPharmacies).doc(pharmacie.id).update({
          'statut': PharmacieStatut.suspendu,
          'suspended_at': FieldValue.serverTimestamp(),
        });
        break;
      case 'supprimer':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Supprimer cette pharmacie ?'),
            content: Text('Cette action supprimera définitivement ${pharmacie.nom}. Irréversible.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await firestore.collection(AppConstants.colPharmacies).doc(pharmacie.id).delete();
        }
        break;
    }
  }
}

class AdminPharmaciesScreen extends ConsumerWidget {
  const AdminPharmaciesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AdminDashboardScreen();
  }
}

class AdminTarifsScreen extends ConsumerStatefulWidget {
  const AdminTarifsScreen({super.key});
  @override
  ConsumerState<AdminTarifsScreen> createState() => _AdminTarifsState();
}

class _AdminTarifsState extends ConsumerState<AdminTarifsScreen> {
  final _fraisCtrl = TextEditingController();
  final _detaillantCtrl = TextEditingController();
  final _grossisteCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTarifs();
  }

  Future<void> _loadTarifs() async {
    final snap = await FirebaseFirestore.instance
        .collection(AppConstants.colConfig)
        .doc(AppConstants.docTarifs)
        .get();
    if (snap.exists) {
      final data = snap.data()!;
      _fraisCtrl.text = '${data['frais_creation_compte'] ?? 5000}';
      _detaillantCtrl.text = '${data['abonnement_mensuel_detaillant'] ?? 10000}';
      _grossisteCtrl.text = '${data['abonnement_mensuel_grossiste'] ?? 25000}';
    }
  }

  Future<void> _sauvegarder() async {
    setState(() => _loading = true);
    await FirebaseFirestore.instance
        .collection(AppConstants.colConfig)
        .doc(AppConstants.docTarifs)
        .set({
      'frais_creation_compte': double.tryParse(_fraisCtrl.text) ?? 5000,
      'abonnement_mensuel_detaillant': double.tryParse(_detaillantCtrl.text) ?? 10000,
      'abonnement_mensuel_grossiste': double.tryParse(_grossisteCtrl.text) ?? 25000,
      'updated_at': FieldValue.serverTimestamp(),
    });
    setState(() => _loading = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarifs mis à jour !')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Tarifs & Prix'),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Configuration des tarifs', style: AppTextStyles.h4),
              const SizedBox(height: 4),
              Text('Modifiez les montants appliqués à toutes les pharmacies', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              _field(_fraisCtrl, 'Frais de création de compte (FC)', Icons.account_circle_outlined),
              const SizedBox(height: 14),
              _field(_detaillantCtrl, 'Abonnement mensuel Détaillant (FC)', Icons.storefront_outlined),
              const SizedBox(height: 14),
              _field(_grossisteCtrl, 'Abonnement mensuel Grossiste (FC)', Icons.warehouse_outlined),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sauvegarder,
                  child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Enregistrer les tarifs'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixText: 'FC',
      ),
    );
  }

  @override
  void dispose() {
    _fraisCtrl.dispose();
    _detaillantCtrl.dispose();
    _grossisteCtrl.dispose();
    super.dispose();
  }
}
