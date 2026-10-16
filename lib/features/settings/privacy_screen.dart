import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../services/public_information.dart';

class PrivacyLinks extends StatelessWidget {
  const PrivacyLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    children: [
      TextButton(
        onPressed: () => context.push('/confidentialite'),
        child: const Text('Confidentialité'),
      ),
      TextButton(
        onPressed: () => context.push('/suppression-compte'),
        child: const Text('Demander la suppression du compte'),
      ),
    ],
  );
}

class PrivacyScreen extends ConsumerStatefulWidget {
  final bool deletion;

  const PrivacyScreen({super.key, this.deletion = false});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _confirmed = false;
  bool _opening = false;
  String? _message;

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final opened = await ref.read(publicLinkLauncherProvider)(uri);
      if (!mounted) return;
      setState(() {
        _message = opened
            ? uri.scheme == 'mailto'
                  ? 'Le brouillon a été ouvert. Vérifiez-le et envoyez-le depuis votre messagerie : aucune demande n’est envoyée automatiquement.'
                  : null
            : 'Ouverture impossible. Copiez l’adresse affichée et contactez le support depuis votre messagerie.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Ouverture impossible. Utilisez les coordonnées affichées.';
        });
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.deletion ? 'Suppression du compte' : 'Confidentialité',
      ),
      leading: BackButton(
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/login');
          }
        },
      ),
    ),
    body: SafeArea(
      child: ref
          .watch(publicInformationProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(publicInformationProvider),
                child: const Text('Informations indisponibles. Réessayer'),
              ),
            ),
            data: (information) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  information.appName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (!information.ready)
                  const Text(
                    'Version de préparation : les coordonnées et la politique doivent encore être validées avant publication.',
                  )
                else ...[
                  Text('Éditeur : ${information.publisherName}'),
                  SelectableText(information.supportEmail),
                  Text('Mise à jour : ${information.effectiveDate}'),
                ],
                const SizedBox(height: 20),
                if (widget.deletion) ...[
                  Text(information.deletionWarning),
                  const SizedBox(height: 16),
                  for (final step in information.deletionSteps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(step),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmed,
                    onChanged: (value) =>
                        setState(() => _confirmed = value == true),
                    title: const Text(
                      'Je suis habilité à faire cette demande et je comprends qu’elle concerne toute la pharmacie.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('request_account_deletion'),
                    onPressed: information.ready && _confirmed && !_opening
                        ? () => _open(information.deletionEmail)
                        : null,
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Préparer ma demande par email'),
                  ),
                  const Text(
                    'Vous devez envoyer le message depuis votre messagerie. Aucun compte ni aucune donnée ne sont effacés par ce bouton.',
                  ),
                ] else ...[
                  for (final section in information.sections) ...[
                    Text(
                      section['title']!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(section['body']!),
                    const SizedBox(height: 20),
                  ],
                  TextButton(
                    onPressed: () => context.push('/suppression-compte'),
                    child: const Text('Demander la suppression du compte'),
                  ),
                ],
                if (information.ready) ...[
                  TextButton(
                    onPressed: _opening
                        ? null
                        : () => _open(
                            widget.deletion
                                ? information.deletionUrl
                                : information.privacyUrl,
                          ),
                    child: const Text('Ouvrir la page Web'),
                  ),
                  SelectableText(
                    (widget.deletion
                            ? information.deletionUrl
                            : information.privacyUrl)
                        .toString(),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!, semanticsLabel: _message),
                  ),
              ],
            ),
          ),
    ),
  );
}
