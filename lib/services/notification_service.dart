import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../local_database/local_database.dart';

/// NotificationService gère :
/// - FCM (notifications push cloud)
/// - Notifications locales (alertes stock, expiration)
/// - Enregistrement des tokens pour le ciblage

class NotificationService {
  static final _fln = FlutterLocalNotificationsPlugin();
  static final _fcm = FirebaseMessaging.instance;

  static const _channelStock = AndroidNotificationChannel(
    'stock_alerts',
    'Alertes Stock',
    description: 'Notifications de stock faible et ruptures',
    importance: Importance.high,
  );

  static const _channelAbonnement = AndroidNotificationChannel(
    'subscription_alerts',
    'Alertes Abonnement',
    description: 'Rappels de renouvellement d\'abonnement',
    importance: Importance.high,
  );

  static Future<void> init() async {
    // Demande de permission (essentiel pour iOS et Android 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Permissions de notification refusées');
      return;
    }

    // Initialisation notifications locales
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _fln.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Création des canaux Android
    final androidPlugin = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channelStock);
    await androidPlugin?.createNotificationChannel(_channelAbonnement);

    // Écoute des messages en arrière-plan et premier plan
    FirebaseMessaging.onMessage.listen(_onFcmMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onFcmTapped);

    // Token initial
    final token = await _fcm.getToken();
    if (token != null) {
      _currentFcmToken = token;
    }
    _fcm.onTokenRefresh.listen((newToken) => _currentFcmToken = newToken);
  }

  static String? _currentFcmToken;

  /// Sauvegarde le token dans Firestore pour une pharmacie spécifique
  static Future<void> updateTokenForPharmacie(String pharmacieId) async {
    if (_currentFcmToken == null) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.colPharmacies)
          .doc(pharmacieId)
          .update({
        'fcm_token': _currentFcmToken,
        'last_token_update': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Erreur sauvegarde token FCM: $e');
    }
  }

  static void _onFcmMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _fln.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'general_alerts',
          'Alertes Générales',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: message.data['type'], // On passe le type pour le routing au clic
    );
  }

  static void _onFcmTapped(RemoteMessage message) {
    _handleRouting(message.data['type']);
  }

  static void _onNotificationTap(NotificationResponse response) {
    _handleRouting(response.payload);
  }

  static void _handleRouting(String? type) {
    // Ici on pourra utiliser le router pour naviguer
    // ex: router.go('/stock') si type == 'stock_alert'
    debugPrint('Navigation vers notification type: $type');
  }

  // ... (Garder le reste des méthodes de vérification de stock)
}
