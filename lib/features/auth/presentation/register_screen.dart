import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'Congo');
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _owner,
      _phone,
      _address,
      _city,
      _country,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (ref.read(currentUserProvider) == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authServiceProvider)
          .creerPharmacie(
            nom: _name.text,
            telephone: _phone.text,
            adresse: _address.text,
            ville: _city.text,
            pays: _country.text,
            proprietaireNom: _owner.text,
          );
      if (mounted) context.go('/dashboard');
    } catch (error) {
      if (mounted)
        PfSnackbar.error(context, 'Configuration impossible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Configurer votre pharmacie'),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Déconnexion',
          onPressed: _busy
              ? null
              : () => ref.read(authServiceProvider).logout(),
        ),
      ],
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Cette configuration est effectuée une seule fois. Les autres appareils retrouveront la même pharmacie avec le même compte.',
          ),
          const SizedBox(height: 20),
          _field(_name, 'Nom de la pharmacie', Icons.local_pharmacy_outlined),
          _field(_owner, 'Responsable', Icons.person_outline),
          _field(
            _phone,
            'Téléphone',
            Icons.phone_outlined,
            keyboard: TextInputType.phone,
          ),
          _field(_address, 'Adresse', Icons.location_on_outlined),
          _field(_city, 'Ville', Icons.location_city),
          _field(_country, 'Pays', Icons.public),
          PfButton(
            label: 'Enregistrer ma pharmacie',
            isLoading: _busy,
            onPressed: _submit,
            fullWidth: true,
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: PfTextField(
      controller: controller,
      label: label,
      prefixIcon: icon,
      keyboardType: keyboard,
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Champ requis' : null,
    ),
  );
}
