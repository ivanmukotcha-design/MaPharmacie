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
      floatingActionButton: pharmacie == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddDialog(context),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                'Ajouter',
                style: AppTextStyles.label.copyWith(color: Colors.white),
              ),
            ),
      body: pharmacie == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<FournisseurModel>>(
              future: ref.watch(fournisseursProvider.future),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError)
                  return Center(
                    child: Text('Chargement impossible : ${snap.error}'),
                  );
                final fournisseurs = snap.data ?? [];

                if (fournisseurs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_shipping_outlined,
                            size: 64,
                            color: AppColors.textMuted.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'Aucun fournisseur',
                            style: AppTextStyles.h4,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Ajoutez vos fournisseurs partenaires',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    100,
                  ),
                  itemCount: fournisseurs.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final f = fournisseurs[i];
                    return _FournisseurCard(
                      fournisseur: f,
                      onDelete: () => _delete(f),
                      onEdit: () => _showAddDialog(context, f),
                    );
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
        title: const Text('Archiver ?'),
        content: Text(
          'Archiver ${f.nom} sans supprimer les références historiques ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref
            .read(fournisseurRepositoryProvider)
            .deleteFournisseur(f.pharmacieId, f.id);
      } catch (error) {
        if (mounted) PfSnackbar.error(context, 'Archivage impossible : $error');
      }
    }
  }

  void _showAddDialog(BuildContext context, [FournisseurModel? fournisseur]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddFournisseurSheet(fournisseur: fournisseur),
    );
  }
}

class _FournisseurCard extends StatelessWidget {
  final FournisseurModel fournisseur;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const _FournisseurCard({
    required this.fournisseur,
    this.onDelete,
    this.onEdit,
  });

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
              borderRadius: AppBorderRadius.md,
            ),
            child: Center(
              child: Text(
                fournisseur.nom.isEmpty
                    ? '?'
                    : fournisseur.nom[0].toUpperCase(),
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
                  Text(
                    fournisseur.telephone,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.phone_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: () => _appeler(fournisseur.telephone),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.danger,
              size: 22,
            ),
            onPressed: onDelete,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 22),
            onPressed: onEdit,
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
  final FournisseurModel? fournisseur;

  const _AddFournisseurSheet({this.fournisseur});

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
  void initState() {
    super.initState();
    final supplier = widget.fournisseur;
    if (supplier != null) {
      _nomCtrl.text = supplier.nom;
      _telCtrl.text = supplier.telephone;
      _emailCtrl.text = supplier.email;
      _adresseCtrl.text = supplier.adresse;
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _adresseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
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
                  borderRadius: AppBorderRadius.sm,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              widget.fournisseur == null
                  ? 'Nouveau fournisseur'
                  : 'Modifier le fournisseur',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: AppSpacing.lg),
            PfTextField(
              controller: _nomCtrl,
              label: 'Nom du fournisseur *',
              prefixIcon: Icons.business_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            PfTextField(
              controller: _telCtrl,
              label: 'Téléphone',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.sm),
            PfTextField(
              controller: _emailCtrl,
              label: 'Email',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.sm),
            PfTextField(
              controller: _adresseCtrl,
              label: 'Adresse',
              prefixIcon: Icons.location_on_outlined,
            ),
            const SizedBox(height: AppSpacing.lg),
            PfButton(
              label: 'Enregistrer le fournisseur',
              isLoading: _loading,
              onPressed: _save,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_loading) return;
    if (_nomCtrl.text.trim().isEmpty) {
      PfSnackbar.error(context, 'Le nom est requis');
      return;
    }

    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;

    setState(() => _loading = true);
    try {
      final f = FournisseurModel(
        id: widget.fournisseur?.id ?? const Uuid().v4(),
        pharmacieId: pharmacie.id,
        nom: _nomCtrl.text.trim(),
        telephone: _telCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        adresse: _adresseCtrl.text.trim(),
        createdAt: widget.fournisseur?.createdAt ?? DateTime.now(),
        revision: widget.fournisseur?.revision ?? 0,
        notes: widget.fournisseur?.notes,
      );

      await ref.read(fournisseurRepositoryProvider).saveFournisseur(f);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) PfSnackbar.error(context, 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
