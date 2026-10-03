import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/auth_provider.dart';
import '../../core/errors/user_message.dart';
import '../../repositories/repository_access.dart';
import '../../services/backup_cipher.dart';
import '../../services/backup_service.dart';
import '../../services/sync_service.dart';

final backupFilesProvider = Provider<BackupFiles>((ref) => BackupFiles());

class BackupFiles {
  Future<Uint8List?> pick() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: true);
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > BackupCipher.maxFileBytes) {
      throw const FormatException('Le fichier dépasse la limite de 32 Mo.');
    }
    final stream =
        file.readStream ??
        (file.path == null ? null : File(file.path!).openRead());
    if (stream == null) {
      throw const FormatException('Impossible de lire ce fichier.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > BackupCipher.maxFileBytes) {
        throw const FormatException('Le fichier dépasse la limite de 32 Mo.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<void> share(
    Uint8List bytes,
    Rect? origin,
    void Function() checkAccess,
  ) async {
    checkAccess();
    final directory = await getTemporaryDirectory();
    checkAccess();
    final file = File(
      '${directory.path}/PharmaFlow_${DateTime.now().microsecondsSinceEpoch}.pfbackup',
    );
    await file.writeAsBytes(bytes, flush: true);
    checkAccess();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream')],
      text: 'Sauvegarde chiffrée PharmaFlow',
      sharePositionOrigin: origin,
    );
  }
}

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function(String owner) action) async {
    if (_busy) return;
    final owner = ref.read(currentUserProvider)?.uid;
    if (owner == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(owner);
    } catch (error) {
      if (mounted) {
        final message = userMessage(error);
        setState(() => _message = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _password({required bool create}) => showDialog<String>(
    context: context,
    builder: (context) => _PasswordDialog(create: create),
  );

  Future<void> _create(String owner) async {
    final password = await _password(create: true);
    if (password == null || !mounted) return;
    final access = ref.read(repositoryAccessProvider);
    access.read(owner);
    final files = ref.read(backupFilesProvider);
    final bytes = await ref.read(backupServiceProvider).create(owner, password);
    if (!mounted) return;
    access.read(owner);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await files.share(bytes, origin, () => access.read(owner));
    if (mounted) {
      setState(
        () => _message =
            'Copie chiffrée préparée. Enregistrez-la hors de ce téléphone et conservez sa phrase secrète séparément.',
      );
    }
  }

  Future<void> _restore(String owner) async {
    final access = ref.read(repositoryAccessProvider);
    access.write(owner);
    final service = ref.read(backupServiceProvider);
    final sync = ref.read(syncServiceProvider);
    final bytes = await ref.read(backupFilesProvider).pick();
    if (bytes == null || !mounted) return;
    access.write(owner);
    final encrypted = BackupCipher.readEnvelope(
      bytes,
    ).containsKey('ciphertext');
    final password = encrypted ? await _password(create: false) : '';
    if (password == null || !mounted) return;
    final snapshot = await service.inspect(bytes, password, owner);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Vérifier la restauration'),
        content: SingleChildScrollView(
          child: Text(
            'Copie du ${DateFormat('dd/MM/yyyy HH:mm').format(snapshot.date)}\n'
            '${snapshot.count('medicaments')} produits • ${snapshot.count('ventes')} ventes\n'
            '${snapshot.count('sync_queue')} opération(s) en attente\n\n'
            '${snapshot.encrypted ? '' : 'Attention : ancienne copie JSON non chiffrée. Importez uniquement votre propre fichier de confiance.\n\n'}'
            'Les données des autres comptes ne seront pas modifiées. Les fiches déjà présentes seront conservées, '
            'sauf celles liées aux opérations en attente de cette copie, qui seront restaurées localement pour vérification.\n\n'
            'Aucune donnée ne sera supprimée du serveur. Après restauration, vérifiez la synchronisation et les éventuels conflits. '
            'N’utilisez pas la même copie pour reprendre des opérations hors ligne sur plusieurs appareils à la fois.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Restaurer cette copie'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    access.write(owner);
    await sync.maintenance(() => service.restore(snapshot, owner));
    sync.scheduleSync();
    if (mounted) {
      setState(
        () => _message =
            'Copie restaurée localement. Ouvrez le suivi de synchronisation avant de reprendre les ventes.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sauvegarde et restauration')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.enhanced_encryption_outlined, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Une copie protégée de vos données',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'La sauvegarde contient les données locales de cette pharmacie, y compris les opérations non envoyées. '
          'Elle ne contient pas votre mot de passe de connexion.\n\n'
          'Choisissez une phrase secrète dédiée : sans elle, la nouvelle sauvegarde ne pourra pas être restaurée. '
          'Enregistrez le fichier sur un autre support, pas seulement sur ce téléphone.\n\n'
          'La restauration nécessite le même compte de pharmacie. Elle ne remplace pas une sauvegarde du serveur Firebase.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(_create),
          icon: const Icon(Icons.save_alt),
          label: const Text('Créer une sauvegarde chiffrée'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || !ref.watch(pharmacieWritableProvider)
              ? null
              : () => _run(_restore),
          icon: const Icon(Icons.restore),
          label: const Text('Restaurer une sauvegarde'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_message!),
          ),
      ],
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  final bool create;
  const _PasswordDialog({required this.create});
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.create ? 'Protéger la sauvegarde' : 'Ouvrir la sauvegarde',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.create
                  ? 'Utilisez une phrase secrète d’au moins 12 caractères, différente du mot de passe du compte. Elle ne sera pas enregistrée dans l’application.'
                  : 'Saisissez la phrase secrète choisie lors de la création de cette sauvegarde.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Phrase secrète'),
              validator: (value) =>
                  value == null ||
                      value.isEmpty ||
                      widget.create &&
                          (value.runes.length < 12 || value.trim().isEmpty)
                  ? (widget.create
                        ? 'Au moins 12 caractères sont nécessaires.'
                        : 'Saisissez la phrase secrète.')
                  : null,
            ),
            if (widget.create)
              TextFormField(
                controller: _confirmation,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Confirmer la phrase secrète',
                ),
                validator: (value) => value != _password.text
                    ? 'Les phrases secrètes ne correspondent pas.'
                    : null,
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _password.text);
          }
        },
        child: const Text('Continuer'),
      ),
    ],
  );
}
