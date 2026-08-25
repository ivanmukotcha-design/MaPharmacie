import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../config/auth_provider.dart';
import '../models/models.dart';
import '../repositories/medicament_repository.dart';
import '../repositories/vente_repository.dart';
import '../services/export_service.dart';
import '../shared/widgets/pf_snackbar.dart';

// ─── REPORTS SCREEN ───────────────────────────────────────────────────────────
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Rapports & Exports')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _sectionTitle('Rapports de stock'),
          _reportCard(
            context,
            icon: Icons.medication_outlined,
            titre: 'Liste complète des médicaments',
            description: 'Tous les médicaments avec quantités et prix',
            onExcelTap: () => _handleExport(context, ref, 'excel', 'stock_complet'),
            onWordTap: () => _handleExport(context, ref, 'word', 'stock_complet'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _reportCard(
            context,
            icon: Icons.warning_amber_outlined,
            titre: 'Stock faible & ruptures',
            description: 'Médicaments sous le seuil d\'alerte',
            color: AppColors.warning,
            onExcelTap: () => _handleExport(context, ref, 'excel', 'stock_faible'),
            onWordTap: () => _handleExport(context, ref, 'word', 'stock_faible'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _reportCard(
            context,
            icon: Icons.event_busy_outlined,
            titre: 'Produits expirés / bientôt expirés',
            description: 'Médicaments à retirer ou surveiller',
            color: AppColors.danger,
            onExcelTap: () => _handleExport(context, ref, 'excel', 'expires'),
            onWordTap: () => _handleExport(context, ref, 'word', 'expires'),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Rapports de ventes'),
          _reportCard(
            context,
            icon: Icons.receipt_long_outlined,
            titre: 'Historique des ventes',
            description: 'Toutes les ventes avec détails et bénéfices',
            onExcelTap: () => _handleExport(context, ref, 'excel', 'ventes'),
            onWordTap: () => _handleExport(context, ref, 'word', 'ventes'),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionTitle('Rapports fournisseurs'),
          _reportCard(
            context,
            icon: Icons.local_shipping_outlined,
            titre: 'Liste des fournisseurs',
            description: 'Coordonnées et médicaments par fournisseur',
            onExcelTap: () => _handleExport(context, ref, 'excel', 'fournisseurs'),
            onWordTap: () => _handleExport(context, ref, 'word', 'fournisseurs'),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: AppTextStyles.h4),
    );
  }

  Widget _reportCard(
    BuildContext context, {
    required IconData icon,
    required String titre,
    required String description,
    Color? color,
    required VoidCallback onExcelTap,
    required VoidCallback onWordTap,
  }) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppBorderRadius.md,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: AppBorderRadius.sm),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: AppTextStyles.label),
                Text(description, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _exportBtn('Excel', Colors.green, onExcelTap),
        ],
      ),
    );
  }

  Widget _exportBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppBorderRadius.sm,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _handleExport(BuildContext context, WidgetRef ref, String format, String type) async {
    if (format != 'excel') {
      PfSnackbar.info(context, 'Le format $format sera bientôt disponible.');
      return;
    }

    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;

    PfSnackbar.info(context, 'Préparation de l\'export Excel...');

    try {
      if (type.startsWith('stock')) {
        final meds = await ref.read(medicamentRepositoryProvider).getMedicaments(pharmacie.id);
        
        List<MedicamentModel> filtered = meds;
        if (type == 'stock_faible') {
          filtered = meds.where((m) => m.estStockFaible || m.estEnRupture).toList();
        }

        await ExportService.exportStockToExcel(filtered);
      } 
      else if (type == 'ventes') {
        final ventes = await ref.read(venteRepositoryProvider).getHistoriqueVentes(pharmacie.id);
        await ExportService.exportVentesToExcel(ventes);
      }
      else {
        PfSnackbar.info(context, 'Cet export est en cours de développement.');
        return;
      }
      
      if (context.mounted) PfSnackbar.success(context, 'Rapport généré avec succès !');
    } catch (e) {
      if (context.mounted) PfSnackbar.error(context, 'Erreur lors de l\'export : $e');
    }
  }
}

// ─── SUPPORT SCREEN ───────────────────────────────────────────────────────────
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _email = 'support@pharmaflow.app';
  static const _whatsapp = '+243 81 000 0000';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
              borderRadius: AppBorderRadius.lg,
            ),
            child: Column(children: [
              const Icon(Icons.headset_mic_outlined, color: Colors.white, size: 48),
              const SizedBox(height: AppSpacing.sm),
              Text('Support Ma Pharmacie', style: AppTextStyles.h3.copyWith(color: Colors.white)),
              const SizedBox(height: AppSpacing.xs),
              Text('Nous sommes là pour vous aider', style: AppTextStyles.body.copyWith(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Nous contacter', style: AppTextStyles.h4),
          const SizedBox(height: AppSpacing.sm),
          _contactCard(
            icon: Icons.email_outlined,
            titre: 'Email support',
            sous: _email,
            color: AppColors.info,
            onTap: () => _ouvrirEmail(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _contactCard(
            icon: Icons.chat_outlined,
            titre: 'WhatsApp',
            sous: _whatsapp,
            color: Colors.green,
            onTap: () => _ouvrirWhatsapp(),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Questions fréquentes', style: AppTextStyles.h4),
          const SizedBox(height: AppSpacing.sm),
          ..._faqs.map((faq) => _faqItem(faq[0], faq[1])),
        ],
      ),
    );
  }

  Widget _contactCard({required IconData icon, required String titre, required String sous, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppBorderRadius.md,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: AppBorderRadius.sm),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: AppTextStyles.label),
            Text(sous, style: AppTextStyles.body.copyWith(color: color)),
          ])),
          const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  Widget _faqItem(String question, String reponse) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(question, style: AppTextStyles.label),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(reponse, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  void _ouvrirEmail() async {
    final uri = Uri.parse('mailto:$_email?subject=Support Ma Pharmacie');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  void _ouvrirWhatsapp() async {
    final tel = _whatsapp.replaceAll(' ', '').replaceAll('+', '');
    final uri = Uri.parse('https://wa.me/$tel');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  static const _faqs = [
    ['Comment ajouter un médicament ?', 'Allez dans Stock, puis cliquez sur le bouton + en bas à droite pour ajouter un nouveau médicament.'],
    ['Que faire si j\'oublie mon mot de passe ?', 'Sur l\'écran de connexion, cliquez sur "Mot de passe oublié" et entrez votre email. Vous recevrez un lien de réinitialisation.'],
    ['L\'application fonctionne-t-elle sans internet ?', 'Oui, Ma Pharmacie fonctionne en mode hors ligne. Toutes les données sont synchronisées dès que la connexion est rétablie.'],
    ['Comment exporter mes rapports ?', 'Dans la section Rapports, choisissez le type de rapport et cliquez sur Excel ou Word selon votre préférence.'],
  ];
}

// ─── SETTINGS SCREEN ─────────────────────────────────────────────────────────
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmacieAsync = ref.watch(currentPharmacieProvider);
    final pharmacie = pharmacieAsync.valueOrNull;
    final themeMode = ref.watch(themeModeProvider);

    String themeLabel = 'Système';
    if (themeMode == ThemeMode.light) themeLabel = 'Clair';
    if (themeMode == ThemeMode.dark) themeLabel = 'Sombre';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          // Profil pharmacie
          if (pharmacie != null) ...[
            Container(
              margin: const EdgeInsets.all(AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppBorderRadius.md,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: AppBorderRadius.md),
                  child: const Icon(Icons.local_pharmacy_rounded, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pharmacie.nom, style: AppTextStyles.h4),
                  Text(pharmacie.code, style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                  Text(pharmacie.typePharmacie == 'grossiste' ? 'Pharmacie grossiste' : 'Pharmacie détaillant',
                      style: AppTextStyles.small.copyWith(color: AppColors.textSecondary)),
                ])),
              ]),
            ),
          ],

          _settingsGroup('Application', [
            _settingsTile(
              context, 
              Icons.brightness_6_outlined, 
              'Thème', 
              themeLabel, 
              () => _showThemeDialog(context, ref),
            ),
            _settingsTile(context, Icons.notifications_outlined, 'Notifications', 'Alertes stock', () {}),
            _settingsTile(context, Icons.language_outlined, 'Langue', 'Français', () {}),
          ]),

          _settingsGroup('Compte', [
            _settingsTile(context, Icons.business_outlined, 'Informations pharmacie', '', () {}),
            _settingsTile(context, Icons.lock_outline, 'Changer le mot de passe', '', () {}),
          ]),

          _settingsGroup('Données', [
            _settingsTile(context, Icons.sync_outlined, 'Synchroniser maintenant', '', () {}),
            _settingsTile(context, Icons.backup_outlined, 'Sauvegarde locale', '', () {}),
          ]),

          _settingsGroup('Support', [
            _settingsTile(context, Icons.help_outline, 'Centre d\'aide', '', () {}),
            _settingsTile(context, Icons.privacy_tip_outlined, 'Politique de confidentialité', '', () {}),
          ]),

          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authServiceProvider).logout();
              },
              icon: const Icon(Icons.logout, color: AppColors.danger),
              label: const Text('Se déconnecter', style: TextStyle(color: AppColors.danger, fontFamily: 'Poppins')),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),

          Center(
            child: Text('Ma Pharmacie v1.0.0', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.read(themeModeProvider);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choisir le thème'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Clair'),
              value: ThemeMode.light,
              groupValue: currentTheme,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).state = val!;
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Sombre'),
              value: ThemeMode.dark,
              groupValue: currentTheme,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).state = val!;
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Système (automatique)'),
              value: ThemeMode.system,
              groupValue: currentTheme,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).state = val!;
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsGroup(String titre, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Text(titre, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted, letterSpacing: 0.5)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppBorderRadius.md,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              return Column(
                children: [
                  e.value,
                  if (e.key < items.length - 1) const Divider(height: 1, indent: 56),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Widget _settingsTile(BuildContext context, IconData icon, String titre, String sous, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppBorderRadius.sm),
        child: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
      title: Text(titre, style: AppTextStyles.label),
      subtitle: sous.isNotEmpty ? Text(sous, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)) : null,
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
      onTap: onTap,
      dense: true,
    );
  }
}
