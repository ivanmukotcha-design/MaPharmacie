String? validateEmail(String? value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Email valide requis';

String? validatePassword(String? value) =>
    value == null || value.length < 6 ? 'Minimum 6 caractères' : null;

double? parseDecimal(String? value) =>
    double.tryParse((value ?? '').trim().replaceAll(',', '.'));

String? validatePrice(String? value) {
  final number = parseDecimal(value);
  return number == null || !number.isFinite || number < 0
      ? 'Montant positif ou nul requis'
      : null;
}

String? validateQuantity(String? value, {bool positive = false}) {
  final number = int.tryParse((value ?? '').trim());
  return number == null || number < (positive ? 1 : 0)
      ? (positive
            ? 'Entier supérieur à zéro requis'
            : 'Entier positif ou nul requis')
      : null;
}
