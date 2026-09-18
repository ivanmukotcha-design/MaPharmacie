import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/auth_provider.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_text_field.dart';

class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .createAccount(_email.text, _password.text);
      if (mounted) context.go('/configurer');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'email-already-in-use' =>
            'Cet email est déjà utilisé. Connectez-vous ou utilisez « Mot de passe oublié ».',
          'invalid-email' => 'Saisissez une adresse email valide.',
          'weak-password' || 'password-does-not-meet-requirements' =>
            'Choisissez un mot de passe plus robuste.',
          'network-request-failed' =>
            'Vérifiez votre connexion Internet puis réessayez.',
          'too-many-requests' => 'Trop de tentatives. Réessayez plus tard.',
          'operation-not-allowed' =>
            'La création de comptes n’est pas encore activée. Contactez le support.',
          _ => 'Impossible de créer le compte. Réessayez plus tard.',
        };
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Impossible de créer le compte. Réessayez plus tard.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Créer un compte')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Créez un seul compte pour votre pharmacie. Ses autres utilisateurs et appareils se connecteront avec ces mêmes identifiants.',
            ),
            const SizedBox(height: 24),
            PfTextField(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.email_outlined,
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            PfTextField(
              controller: _password,
              label: 'Mot de passe',
              obscureText: true,
              prefixIcon: Icons.lock_outline,
              validator: validatePassword,
            ),
            const SizedBox(height: 16),
            PfTextField(
              controller: _confirmation,
              label: 'Confirmer le mot de passe',
              obscureText: true,
              prefixIcon: Icons.lock_outline,
              validator: (value) => value == _password.text
                  ? null
                  : 'Les mots de passe ne correspondent pas.',
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            PfButton(
              label: 'Créer mon compte',
              onPressed: _createAccount,
              isLoading: _busy,
              fullWidth: true,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _busy ? null : () => context.go('/login'),
              child: const Text('Déjà un compte ? Se connecter'),
            ),
          ],
        ),
      ),
    ),
  );
}
