import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/auth_provider.dart';
import '../../services/pharmacie_settings_service.dart';
import 'pf_snackbar.dart';

class WholesaleSetting extends ConsumerStatefulWidget {
  const WholesaleSetting({super.key});

  @override
  ConsumerState<WholesaleSetting> createState() => _WholesaleSettingState();
}

class _WholesaleSettingState extends ConsumerState<WholesaleSetting> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final pharmacie = ref.watch(currentPharmacieProvider).valueOrNull;
    return SwitchListTile(
      title: const Text('Tarifs de gros'),
      subtitle: Text(
        _saving
            ? 'Enregistrement…'
            : 'Facultatifs, en plus du détail. Réglage commun à tous les appareils, connexion nécessaire.',
      ),
      value: ref.watch(wholesaleEnabledProvider),
      onChanged: _saving || pharmacie == null
          ? null
          : (enabled) async {
              setState(() => _saving = true);
              try {
                await ref
                    .read(pharmacieSettingsServiceProvider)
                    .setWholesaleEnabled(pharmacie.id, enabled);
              } catch (error) {
                if (context.mounted) PfSnackbar.error(context, '$error');
              } finally {
                if (mounted) setState(() => _saving = false);
              }
            },
    );
  }
}
