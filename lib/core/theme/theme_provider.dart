import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider pour gérer le mode d'affichage de l'application
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Extension pour faciliter l'accès au mode sombre
extension ThemeModeExtension on ThemeMode {
  bool isDark(BuildContext context) {
    if (this == ThemeMode.dark) return true;
    if (this == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }
}
