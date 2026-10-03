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
    final status = profile.valueOrNull?.accessStatus;
    final pending = status == 'pending';
    final suspended = status == 'suspended';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          error
              ? 'Vérification indisponible'
              : pending
              ? 'Activation en attente'
              : suspended
              ? 'Compte suspendu'
              : 'Accès indisponible',
        ),
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
                    : pending
                    ? 'Votre compte est en attente d’activation après la vente de l’application. Contactez votre fournisseur en indiquant l’email de votre compte. L’activation apparaîtra ici dès sa réception.'
                    : suspended
                    ? 'L’accès aux opérations est suspendu. Vos données ne sont pas supprimées. Vous pouvez créer une sauvegarde locale et contacter le support.'
                    : 'Ce profil ne correspond pas au compte connecté ou son accès est indisponible. Contactez le support.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (pending || suspended)
                Text(profile.valueOrNull!.email, textAlign: TextAlign.center),
              if (suspended && !error)
                TextButton(
                  onPressed: () => context.push('/sauvegardes'),
                  child: const Text('Sauvegarder mes données locales'),
                ),
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
