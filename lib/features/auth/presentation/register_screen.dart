import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_text_field.dart';
import '../../../shared/widgets/pf_snackbar.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomPharmacieCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _proprietaireCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telephoneCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _paysCtrl = TextEditingController(text: 'Congo');
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  String _typePharmacie = 'detaillant';
  bool _loading = false;
  int _currentStep = 0;

  @override
  void dispose() {
    for (final ctrl in [
      _nomPharmacieCtrl, _usernameCtrl, _proprietaireCtrl, _emailCtrl,
      _telephoneCtrl, _adresseCtrl, _villeCtrl, _paysCtrl,
      _passwordCtrl, _confirmPasswordCtrl,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      // 1. Créer le compte Firebase Auth
      final cred = await ref.read(authServiceProvider).registerWithEmail(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );

      // 2. Créer la pharmacie dans Firestore
      final pharmacie = await ref.read(authServiceProvider).creerPharmacie(
        userId: cred.user!.uid,
        nom: _nomPharmacieCtrl.text.trim(),
        username: _usernameCtrl.text.trim().toLowerCase(),
        email: _emailCtrl.text.trim(),
        telephone: _telephoneCtrl.text.trim(),
        adresse: _adresseCtrl.text.trim(),
        ville: _villeCtrl.text.trim(),
        pays: _paysCtrl.text.trim(),
        typePharmacie: _typePharmacie,
        proprietaireNom: _proprietaireCtrl.text.trim(),
      );

      // 3. Rediriger vers le dashboard
      if (mounted) {
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) PfSnackbar.error(context, 'Erreur: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => context.go('/login'),
        ),
        title: Text(
          'Créer un compte',
          style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() => _currentStep++);
            } else {
              _submit();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) setState(() => _currentStep--);
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Expanded(
                    child: PfButton(
                      label: _currentStep == 2 ? 'Créer mon compte' : 'Continuer',
                      onPressed: details.onStepContinue,
                      isLoading: _loading && _currentStep == 2,
                    ),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Retour'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            _step1Pharmacie(),
            _step2Contact(),
            _step3Compte(),
          ],
        ),
      ),
    );
  }

  Step _step1Pharmacie() {
    return Step(
      title: Text('Votre pharmacie', style: AppTextStyles.label),
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          PfTextField(
            controller: _nomPharmacieCtrl,
            label: 'Nom de la pharmacie',
            hint: 'Pharmacie du Centre',
            prefixIcon: Icons.local_pharmacy_outlined,
            validator: (v) => v?.isEmpty == true ? 'Requis' : null,
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _proprietaireCtrl,
            label: 'Nom du propriétaire',
            hint: 'Dr. Paul',
            prefixIcon: Icons.person_outline,
            validator: (v) => v?.isEmpty == true ? 'Requis' : null,
          ),
          const SizedBox(height: 20),
          Text('Type de pharmacie', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              _typeCard('detaillant', 'Détaillant', Icons.storefront_outlined,
                  'Pour les pharmacies de détail'),
              const SizedBox(width: 12),
              _typeCard('grossiste', 'Grossiste', Icons.warehouse_outlined,
                  'Pour les grossistes en médicaments'),
            ],
          ),
        ],
      ),
    );
  }

  Step _step2Contact() {
    return Step(
      title: Text('Coordonnées', style: AppTextStyles.label),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          PfTextField(
            controller: _telephoneCtrl,
            label: 'Téléphone',
            hint: '+243 81 234 5678',
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (v) => v?.isEmpty == true ? 'Requis' : null,
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _villeCtrl,
            label: 'Ville',
            hint: 'Kinshasa',
            prefixIcon: Icons.location_city_outlined,
            validator: (v) => v?.isEmpty == true ? 'Requis' : null,
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _paysCtrl,
            label: 'Pays',
            hint: 'Congo',
            prefixIcon: Icons.flag_outlined,
            validator: (v) => v?.isEmpty == true ? 'Requis' : null,
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _adresseCtrl,
            label: 'Adresse',
            hint: 'Avenue de la Paix, Quartier...',
            prefixIcon: Icons.home_outlined,
            validator: (v) => v?.isEmpty == true ? 'Requis' : null,
          ),
        ],
      ),
    );
  }

  Step _step3Compte() {
    return Step(
      title: Text('Identifiants', style: AppTextStyles.label),
      isActive: _currentStep >= 2,
      content: Column(
        children: [
          PfTextField(
            controller: _usernameCtrl,
            label: 'Nom d\'utilisateur',
            hint: 'jean_pharma',
            prefixIcon: Icons.alternate_email,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Requis';
              if (v.length < 3) return 'Trop court';
              if (v.contains(' ')) return 'Pas d\'espaces';
              return null;
            },
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _emailCtrl,
            label: 'Email',
            hint: 'pharmacie@email.com',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v?.isEmpty == true) return 'Requis';
              if (!v!.contains('@')) return 'Email invalide';
              return null;
            },
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _passwordCtrl,
            label: 'Mot de passe',
            hint: 'Minimum 6 caractères',
            prefixIcon: Icons.lock_outline,
            obscureText: true,
            validator: (v) {
              if (v?.isEmpty == true) return 'Requis';
              if (v!.length < 6) return 'Minimum 6 caractères';
              return null;
            },
          ),
          const SizedBox(height: 16),
          PfTextField(
            controller: _confirmPasswordCtrl,
            label: 'Confirmer le mot de passe',
            hint: 'Répétez le mot de passe',
            prefixIcon: Icons.lock_outline,
            obscureText: true,
            validator: (v) {
              if (v != _passwordCtrl.text) return 'Les mots de passe ne correspondent pas';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _typeCard(String type, String label, IconData icon, String subtitle) {
    final selected = _typePharmacie == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typePharmacie = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.textMuted, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTextStyles.small.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
