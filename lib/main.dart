import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'config/router.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation de la localisation pour les dates
  await initializeDateFormatting('fr_FR', null);

  // Fixation de l'orientation en portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialisation de Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Erreur lors de l\'initialisation de Firebase : $e');
  }

  // Initialisation du service de notifications
  await NotificationService.init();

  runApp(
    const ProviderScope(
      child: MaPharmacieApp(),
    ),
  );
}

class MaPharmacieApp extends ConsumerWidget {
  const MaPharmacieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Ma Pharmacie',
      debugShowCheckedModeBanner: false,
      
      // Thèmes
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      
      // Navigation
      routerConfig: router,
      
      // Localisation
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('fr', 'CD'), // Congo-Kinshasa
        Locale('en', 'US'),
      ],
      locale: const Locale('fr', 'FR'), // Français par défaut
      
      // Configuration globale de l'UI
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return AnnotatedRegion<SystemUiOverlayStyle>(
          key: const ValueKey('app_system_ui'),
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: isDark ? AppColors.darkBackground : Colors.white,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
