import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_text_field.dart';
import '../../../shared/widgets/pf_snackbar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authServiceProvider)
          .loginWithEmail(
            _usernameCtrl.text.trim().toLowerCase(),
            _passwordCtrl.text,
          );
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) PfSnackbar.error(context, _parseError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(String e) {
    if (e.contains('user-not-found') ||
        e.contains('wrong-password') ||
        e.contains('invalid-credential')) {
      return 'Email ou mot de passe incorrect';
    }
    if (e.contains('too-many-requests'))
      return 'Trop de tentatives. Réessayez plus tard.';
    if (e.contains('network')) return 'Pas de connexion internet';
    return 'Erreur de connexion';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              // Logo & branding
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.local_pharmacy_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppConstants.appName,
                      style: AppTextStyles.h2.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestion pharmaceutique professionnelle',
                      style: AppTextStyles.small.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              Text(
                'Connexion',
                style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Connectez-vous avec votre adresse email',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: 28),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    PfTextField(
                      controller: _usernameCtrl,
                      label: 'Email',
                      hint: 'pharmacie@example.com',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || !v.trim().contains('@'))
                          return 'Email valide requis';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    PfTextField(
                      controller: _passwordCtrl,
                      label: 'Mot de passe',
                      hint: '••••••••',
                      prefixIcon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return 'Mot de passe requis';
                        if (v.length < 6) return 'Minimum 6 caractères';
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showResetDialog(),
                  child: Text(
                    'Mot de passe oublié ?',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              PfButton(
                label: 'Se connecter',
                onPressed: _login,
                isLoading: _loading,
                fullWidth: true,
              ),

              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _loading ? null : () => context.push('/register'),
                child: const Text('Créer un compte'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nouvelle pharmacie ? Créez son compte. Sur les autres appareils, connectez-vous avec le même email et le même mot de passe pour retrouver ses données.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Réinitialiser le mot de passe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Entrez votre email pour recevoir un lien de réinitialisation.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(authServiceProvider)
                    .resetPassword(ctrl.text.trim());
                if (mounted && ctx.mounted) {
                  Navigator.pop(ctx);
                  PfSnackbar.success(
                    context,
                    'Email envoyé ! Vérifiez votre boîte mail.',
                  );
                }
              } catch (_) {
                if (mounted)
                  PfSnackbar.error(context, 'Erreur. Vérifiez l\'email.');
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}
