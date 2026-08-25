import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../config/auth_provider.dart';
import '../../../models/models.dart';
import '../../../repositories/medicament_repository.dart';
import '../../../shared/widgets/pf_button.dart';
import '../../../shared/widgets/pf_text_field.dart';
import '../../../shared/widgets/pf_snackbar.dart';

class MedicamentFormScreen extends ConsumerStatefulWidget {
  final String? medicamentId;
  const MedicamentFormScreen({super.key, this.medicamentId});

  @override
  ConsumerState<MedicamentFormScreen> createState() => _MedicamentFormScreenState();
}

class _MedicamentFormScreenState extends ConsumerState<MedicamentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _isEdit = false;

  // Contrôleurs
  final _nomCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _prixGrossisteCtrl = TextEditingController();
  final _prixDetailCtrl = TextEditingController();
  final _seuilAlerteCtrl = TextEditingController(text: '10');
  final _codeBarresCtrl = TextEditingController();
  final _fournisseurCtrl = TextEditingController();
  
  // Unités
  final _cartonsCtrl = TextEditingController(text: '0');
  final _boitesCtrl = TextEditingController(text: '0');
  final _plaquettesCtrl = TextEditingController(text: '0');
  final _comprimesCtrl = TextEditingController(text: '0');
  final _flaconsCtrl = TextEditingController(text: '0');
  
  // Ratios
  final _cartonsParBoiteCtrl = TextEditingController(text: '20');
  final _boitesParPlaquetteCtrl = TextEditingController(text: '10');
  final _plaquettesParComprimeCtrl = TextEditingController(text: '10');

  DateTime? _dateExpiration;
  String _categorie = 'Antibiotiques';

  final _categories = [
    'Antibiotiques', 'Analgésiques', 'Anti-inflammatoires', 'Antiparasitaires',
    'Vitamines', 'Antipaludéens', 'Antifongiques', 'Antiviraux',
    'Cardiovasculaires', 'Diabétologie', 'Dermatologie', 'Autre',
  ];

  @override
  void initState() {
    super.initState();
    _isEdit = widget.medicamentId != null;
    if (_isEdit) {
      // On utilise WidgetsBinding pour éviter les erreurs de build
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMedicament());
    }
  }

  Future<void> _loadMedicament() async {
    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;

    setState(() => _loading = true);
    final med = await ref.read(medicamentRepositoryProvider).getMedicamentById(
      pharmacie.id, 
      widget.medicamentId!,
    );
    
    if (med != null && mounted) {
      setState(() {
        _nomCtrl.text = med.nom;
        _categorie = med.categorie;
        _descriptionCtrl.text = med.description;
        _prixGrossisteCtrl.text = med.prixGrossiste.toString();
        _prixDetailCtrl.text = med.prixDetail.toString();
        _seuilAlerteCtrl.text = med.seuilAlerte.toString();
        _codeBarresCtrl.text = med.codeBarres ?? '';
        _fournisseurCtrl.text = med.fournisseurNom;
        
        _cartonsCtrl.text = med.unites.cartons.toString();
        _boitesCtrl.text = med.unites.boites.toString();
        _plaquettesCtrl.text = med.unites.plaquettes.toString();
        _comprimesCtrl.text = med.unites.comprimes.toString();
        _flaconsCtrl.text = med.unites.flacons.toString();
        
        _cartonsParBoiteCtrl.text = med.unites.cartonsParBoite.toString();
        _boitesParPlaquetteCtrl.text = med.unites.boitesParPlaquette.toString();
        _plaquettesParComprimeCtrl.text = med.unites.plaquettesParComprime.toString();
        
        _dateExpiration = med.dateExpiration;
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _descriptionCtrl.dispose();
    _prixGrossisteCtrl.dispose();
    _prixDetailCtrl.dispose();
    _seuilAlerteCtrl.dispose();
    _codeBarresCtrl.dispose();
    _fournisseurCtrl.dispose();
    _cartonsCtrl.dispose();
    _boitesCtrl.dispose();
    _plaquettesCtrl.dispose();
    _comprimesCtrl.dispose();
    _flaconsCtrl.dispose();
    _cartonsParBoiteCtrl.dispose();
    _boitesParPlaquetteCtrl.dispose();
    _plaquettesParComprimeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sauvegarder() async {
    if (!_formKey.currentState!.validate()) return;

    final pharmacie = ref.read(currentPharmacieProvider).valueOrNull;
    if (pharmacie == null) return;

    if (!pharmacie.isActif) {
      PfSnackbar.error(context, 'Accès refusé. Renouvelez votre abonnement.');
      return;
    }

    setState(() => _loading = true);
    try {
      final repository = ref.read(medicamentRepositoryProvider);
      
      final medicament = MedicamentModel(
        id: widget.medicamentId ?? const Uuid().v4(),
        pharmacieId: pharmacie.id,
        nom: _nomCtrl.text.trim(),
        categorie: _categorie,
        description: _descriptionCtrl.text.trim(),
        prixGrossiste: double.tryParse(_prixGrossisteCtrl.text) ?? 0,
        prixDetail: double.tryParse(_prixDetailCtrl.text) ?? 0,
        fournisseurId: '', // À lier plus tard avec un sélecteur de fournisseur
        fournisseurNom: _fournisseurCtrl.text.trim(),
        seuilAlerte: int.tryParse(_seuilAlerteCtrl.text) ?? 10,
        unites: UnitesStock(
          cartons: int.tryParse(_cartonsCtrl.text) ?? 0,
          boites: int.tryParse(_boitesCtrl.text) ?? 0,
          plaquettes: int.tryParse(_plaquettesCtrl.text) ?? 0,
          comprimes: int.tryParse(_comprimesCtrl.text) ?? 0,
          flacons: int.tryParse(_flaconsCtrl.text) ?? 0,
          cartonsParBoite: int.tryParse(_cartonsParBoiteCtrl.text) ?? 20,
          boitesParPlaquette: int.tryParse(_boitesParPlaquetteCtrl.text) ?? 10,
          plaquettesParComprime: int.tryParse(_plaquettesParComprimeCtrl.text) ?? 10,
        ),
        estActif: true,
        createdAt: DateTime.now(), // Le repository gérera si c'est un edit
        updatedAt: DateTime.now(),
        dateExpiration: _dateExpiration,
        codeBarres: _codeBarresCtrl.text.trim().isEmpty ? null : _codeBarresCtrl.text.trim(),
      );

      await repository.saveMedicament(medicament, isEdit: _isEdit);

      if (mounted) {
        PfSnackbar.success(context, _isEdit ? 'Médicament modifié' : 'Médicament ajouté');
        context.pop();
      }
    } catch (e) {
      if (mounted) PfSnackbar.error(context, 'Erreur: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _isEdit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier médicament' : 'Nouveau médicament'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Informations générales', [
              PfTextField(
                controller: _nomCtrl,
                label: 'Nom du médicament *',
                hint: 'Ex: Paracétamol 500mg',
                prefixIcon: Icons.medication_outlined,
                validator: (v) => v?.isEmpty == true ? 'Requis' : null,
              ),
              const SizedBox(height: 14),
              _categorieDropdown(),
              const SizedBox(height: 14),
              PfTextField(
                controller: _descriptionCtrl,
                label: 'Description',
                hint: 'Indications, posologie...',
                prefixIcon: Icons.description_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              PfTextField(
                controller: _fournisseurCtrl,
                label: 'Fournisseur',
                hint: 'Nom du fournisseur',
                prefixIcon: Icons.local_shipping_outlined,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PfTextField(
                      controller: _codeBarresCtrl,
                      label: 'Code-barres',
                      hint: '1234567890',
                      prefixIcon: Icons.qr_code_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                      onPressed: () {/* Intégrer scanner plus tard */},
                    ),
                  ),
                ],
              ),
            ]),

            const SizedBox(height: 16),

            _section('Tarifs', [
              Row(
                children: [
                  Expanded(
                    child: PfTextField(
                      controller: _prixGrossisteCtrl,
                      label: 'Prix grossiste (FC)',
                      hint: '0',
                      prefixIcon: Icons.warehouse_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) => v?.isEmpty == true ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PfTextField(
                      controller: _prixDetailCtrl,
                      label: 'Prix détail (FC)',
                      hint: '0',
                      prefixIcon: Icons.storefront_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) => v?.isEmpty == true ? 'Requis' : null,
                    ),
                  ),
                ],
              ),
            ]),

            const SizedBox(height: 16),

            _section('Stock & Unités', [
              _conversionCard(),
              const SizedBox(height: 14),
              Text('Quantité disponible', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _uniteField(_cartonsCtrl, 'Cartons'),
                  const SizedBox(width: 8),
                  _uniteField(_boitesCtrl, 'Boîtes'),
                  const SizedBox(width: 8),
                  _uniteField(_plaquettesCtrl, 'Plaquettes'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _uniteField(_comprimesCtrl, 'Comprimés'),
                  const SizedBox(width: 8),
                  _uniteField(_flaconsCtrl, 'Flacons'),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 14),
              PfTextField(
                controller: _seuilAlerteCtrl,
                label: 'Seuil alerte stock (en boîtes)',
                hint: '10',
                prefixIcon: Icons.warning_amber_outlined,
                keyboardType: TextInputType.number,
                validator: (v) => v?.isEmpty == true ? 'Requis' : null,
              ),
            ]),

            const SizedBox(height: 16),

            _section('Date de péremption', [
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: _dateExpiration != null ? AppColors.primary : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dateExpiration != null
                              ? '${_dateExpiration!.day.toString().padLeft(2, '0')}/${_dateExpiration!.month.toString().padLeft(2, '0')}/${_dateExpiration!.year}'
                              : 'Sélectionner la date d\'expiration',
                          style: AppTextStyles.body.copyWith(
                            color: _dateExpiration != null ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                      ),
                      if (_dateExpiration != null)
                        GestureDetector(
                          onTap: () => setState(() => _dateExpiration = null),
                          child: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 24),

            PfButton(
              label: _isEdit ? 'Enregistrer les modifications' : 'Ajouter le médicament',
              onPressed: _sauvegarder,
              isLoading: _loading,
              fullWidth: true,
              icon: _isEdit ? Icons.save_outlined : Icons.add_circle_outline,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _section(String titre, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: AppTextStyles.h4.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _categorieDropdown() {
    return DropdownButtonFormField<String>(
      value: _categorie,
      decoration: InputDecoration(
        labelText: 'Catégorie',
        prefixIcon: const Icon(Icons.category_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: (v) { if (v != null) setState(() => _categorie = v); },
    );
  }

  Widget _conversionCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.info, size: 16),
              const SizedBox(width: 6),
              Text('Conversion des unités', style: AppTextStyles.caption.copyWith(color: AppColors.info)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _convField(_cartonsParBoiteCtrl, '1 carton =', 'boîtes'),
              const SizedBox(width: 8),
              _convField(_boitesParPlaquetteCtrl, '1 boîte =', 'plaquettes'),
              const SizedBox(width: 8),
              _convField(_plaquettesParComprimeCtrl, '1 plaquette =', 'cps'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _convField(TextEditingController ctrl, String prefix, String suffix) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prefix, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.small,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.info.withOpacity(0.3))),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(suffix, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _uniteField(TextEditingController ctrl, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateExpiration ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateExpiration = picked);
  }
}
