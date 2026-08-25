import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../models/models.dart';
import '../../../repositories/fournisseur_repository.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_snackbar.dart';
import '../../../shared/widgets/pf_text_field.dart';

class FournisseursScreen extends ConsumerStatefulWidget {
  const FournisseursScreen({super.key});

  @override
  ConsumerState<FournisseursScreen> createState() => _FournisseursScreenState();
}

class _FournisseursScreenState extends ConsumerState<FournisseursScreen> {
  @override
  Widget build(BuildContext context) {
    final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Fournisseurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Ajouter', style: AppTextStyles.label.copyWith(color: Colors.white)),
      ),
      body: pharmacie == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<FournisseurModel>>(
              future: ref.read(fournisseurRepositoryProvider).getFournisseurs(pharmacie.id),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final fournisseurs = snap.data ?? [];

                if (fournisseurs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_shipping_outlined,
                              size: 64, color: AppColors.textMuted.withValues(alpha: 0.2)),
                          const SizedBox(height: AppSpacing.md),
                          const Text('Aucun fournisseur', style: AppTextStyles.h4),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Ajoutez vos fournisseurs partenaires',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
                  itemCount: fournisseurs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final f = fournisseurs[i];
                    return _FournisseurCard(fournisseur: f, onDelete: () => _delete(f));
                  },
                );
              },
            ),
    );
  }

  void _delete(FournisseurModel f) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Voulez-vous supprimer le fournisseur ${f.nom} ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(fournisseurRepositoryProvider)
          .deleteFournisseur(f.pharmacieId, f.id);
      setState(() {});
    }
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddFournisseurSheet(onAdded: () => setState(() {})),
    );
  }
}

class _FournisseurCard extends StatelessWidget {
  final FournisseurModel fournisseur;
  final VoidCallback onDelete;

  const _FournisseurCard({required this.fournisseur, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppBorderRadius.lg,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: AppBorderRadius.md),
            child: Center(
              child: Text(
                fournisseur.nom[0].toUpperCase(),
                style: AppTextStyles.h2.copyWith(color: AppColors.secondary),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fournisseur.nom, style: AppTextStyles.label),
                if (fournisseur.telephone.isNotEmpty)
                  Text(fournisseur.telephone,
                      style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: AppColors.primary, size: 22),
            onPressed: () => _appeler(fournisseur.telephone),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  void _appeler(String tel) async {
    final uri = Uri.parse('tel:$tel');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }
}

class _AddFournisseurSheet extends ConsumerStatefulWidget {
  final VoidCallback onAdded;

  const _AddFournisseurSheet({required this.onAdded});

  @override
  ConsumerState<_AddFournisseurSheet> createState() =>
      _AddFournisseurSheetState();
}

class _AddFournisseurSheetState extends ConsumerState<_AddFournisseurSheet> {
  final _nomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: AppBorderRadius.sm))),
          const SizedBox(height: AppSpacing.lg),
          Text('Nouveau fournisseur', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.lg),
          PfTextField(
              controller: _nomCtrl,
              label: 'Nom du fournisseur *',
              prefixIcon: Icons.business_outlined),
          const SizedBox(height: AppSpacing.sm),
          PfTextField(
              controller: _telCtrl,
              label: 'Téléphone',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone),
          const SizedBox(height: AppSpacing.sm),
          PfTextField(
              controller: _emailCtrl,
              label: 'Email',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress),
          const SizedBox(height: AppSpacing.sm),
          PfTextField(
              controller: _adresseCtrl,
              label: 'Adresse',
              prefixIcon: Icons.location_on_outlined),
          const SizedBox(height: AppSpacing.lg),
          PfButton(
            label: 'Enregistrer le fournisseur',
            isLoading: _loading,
            onPressed: _save,
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nomCtrl.text.isEmpty) {
      PfSnackbar.error(context, 'Le nom est requis');
      return;
    }

    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;

    setState(() => _loading = true);
    try {
      final f = FournisseurModel(
        id: const Uuid().v4(),
        pharmacieId: pharmacie.id,
        nom: _nomCtrl.text.trim(),
        telephone: _telCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        adresse: _adresseCtrl.text.trim(),
        createdAt: DateTime.now(),
      );

      await ref.read(fournisseurRepositoryProvider).saveFournisseur(f);
      widget.onAdded();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) PfSnackbar.error(context, 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
