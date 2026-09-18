import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../config/auth_provider.dart';

class AccessScreen extends ConsumerWidget {
  const AccessScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentPharmacieProvider);
    final error = profile.hasError || ref.watch(authStateProvider).hasError;
    return Scaffold(
      appBar: AppBar(
        title: Text(error ? 'Vérification indisponible' : 'Accès indisponible'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 20),
              Text(
                error
                    ? 'Vérifiez votre connexion. Le profil de votre pharmacie doit être accessible avant de continuer.'
                    : 'Ce profil ne correspond pas au compte connecté. Reconnectez-vous avec les identifiants de votre pharmacie.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(currentPharmacieProvider);
                  ref.invalidate(authStateProvider);
                },
                child: const Text('Réessayer'),
              ),
              if (!error)
                TextButton(
                  onPressed: () => context.push('/support'),
                  child: const Text('Contacter le support'),
                ),
              TextButton(
                onPressed: () => ref.read(authServiceProvider).logout(),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
