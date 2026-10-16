import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/auth_provider.dart';
import '../../settings/privacy_screen.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _timer;
  bool _busy = false;
  int _remaining = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_send());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    _remaining = ref.read(authServiceProvider).verificationResendSeconds;
    if (_remaining == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(
        () => _remaining = ref
            .read(authServiceProvider)
            .verificationResendSeconds,
      );
      if (_remaining == 0) timer.cancel();
    });
  }

  String _errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'too-many-requests' =>
          'Trop de demandes. Patientez avant de réessayer.',
        'network-request-failed' =>
          'Vérifiez votre connexion Internet puis réessayez.',
        'user-disabled' ||
        'user-not-found' ||
        'user-token-expired' ||
        'invalid-user-token' =>
          'Votre session n’est plus valide. Déconnectez-vous puis reconnectez-vous.',
        _ => 'Vérification indisponible. Réessayez ou contactez le support.',
      };
    }
    return 'Vérification indisponible. Réessayez ou reconnectez-vous.';
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sent = await ref.read(authServiceProvider).sendVerificationEmail();
      if (!mounted) return;
      setState(
        () => _message = sent
            ? 'Un lien de confirmation a été envoyé. Vérifiez aussi les courriers indésirables.'
            : 'Un lien a déjà été demandé récemment, ou l’adresse est confirmée. Vérifiez vos emails puis appuyez sur « J’ai confirmé mon email ».',
      );
    } catch (error) {
      if (mounted) setState(() => _message = _errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _startCooldown();
        });
      }
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final verified = await ref
          .read(authServiceProvider)
          .refreshEmailVerification();
      if (!mounted) return;
      if (verified) {
        ref.invalidate(authStateProvider);
        ref.invalidate(currentPharmacieProvider);
        context.go('/dashboard');
      } else {
        setState(
          () => _message =
              'L’adresse n’est pas encore confirmée. Ouvrez le lien reçu par email, puis réessayez. Un lien expiré peut être remplacé par un nouvel envoi.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).logout();
      if (mounted) context.go('/login');
    } catch (error) {
      if (mounted) setState(() => _message = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Confirmer votre email'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.mark_email_unread_outlined, size: 56),
          const SizedBox(height: 20),
          Text(
            ref.watch(currentUserProvider)?.email ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          const Text(
            'Ouvrez le lien de confirmation reçu dans cette boîte mail, puis revenez ici. Cette étape vérifie votre accès à l’adresse email, pas le mot de passe de votre messagerie.',
          ),
          const SizedBox(height: 12),
          const Text(
            'La confirmation concerne le compte commun de la pharmacie. Sur chaque appareil déjà connecté, actualisez ensuite la vérification. Elle ne remplace pas l’activation par l’administrateur.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 20),
            Semantics(liveRegion: true, child: Text(_message!)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: const Text('J’ai confirmé mon email'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy || _remaining > 0 ? null : _send,
            child: Text(
              _remaining > 0
                  ? 'Renvoyer dans $_remaining s'
                  : 'Renvoyer le lien',
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          TextButton(
            onPressed: _busy ? null : _logout,
            child: const Text('Se déconnecter / autre adresse'),
          ),
          TextButton(
            onPressed: () => context.push('/support'),
            child: const Text('Contacter le support'),
          ),
          const PrivacyLinks(),
        ],
      ),
    ),
  );
}
