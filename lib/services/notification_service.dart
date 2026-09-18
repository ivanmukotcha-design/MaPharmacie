import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final _local = FlutterLocalNotificationsPlugin();
  static String? _token;
  static String? _boundUid;
  static String? pendingRoute;
  static void Function(String)? onNavigate;
  static bool _initialized = false;

  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);

  static Future<void> init() async {
    if (!supported || _initialized) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _route(response.payload),
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'stock_alerts',
              'Alertes pharmacie',
              importance: Importance.high,
            ),
          );
      FirebaseMessaging.onMessage.listen((message) async {
        final notification = message.notification;
        if (notification == null) return;
        try {
          await _local.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'stock_alerts',
                'Alertes pharmacie',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            payload: message.data['type'] as String?,
          );
        } catch (error) {
          debugPrint('Notification indisponible : $error');
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _route(message.data['type'] as String?),
      );
      messaging.onTokenRefresh.listen((value) {
        _token = value;
        final uid = _boundUid;
        if (uid != null) unawaited(updateTokenForPharmacie(uid));
      });
      _initialized = true;
      _token = await messaging.getToken();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await updateTokenForPharmacie(uid);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _route(initial.data['type'] as String?);
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true) {
        _route(localLaunch?.notificationResponse?.payload);
      }
    } catch (error) {
      debugPrint('Notifications indisponibles : $error');
    }
  }

  static Future<void> updateTokenForPharmacie(String pharmacieId) async {
    if (!supported || FirebaseAuth.instance.currentUser?.uid != pharmacieId)
      return;
    _boundUid = pharmacieId;
    try {
      _token ??= await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 5),
      );
      final token = _token;
      if (token == null || _boundUid != pharmacieId) return;
      await FirebaseFirestore.instance
          .collection('pharmacies')
          .doc(pharmacieId)
          .update({
            'fcm_tokens': FieldValue.arrayUnion([token]),
            'last_token_update': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Enregistrement du token différé : $error');
    }
  }

  static Future<void> detachCurrentUser() async {
    if (!supported) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    _boundUid = null;
    _token = null;
    pendingRoute = null;
    try {
      if (uid != null && token != null) {
        await FirebaseFirestore.instance
            .collection('pharmacies')
            .doc(uid)
            .update({
              'fcm_tokens': FieldValue.arrayRemove([token]),
            })
            .timeout(const Duration(seconds: 5));
      }
    } catch (error) {
      debugPrint('Retrait du token différé : $error');
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 5),
      );
      await _local.cancelAll();
    } catch (error) {
      debugPrint('Nettoyage des notifications indisponible : $error');
    }
  }

  static void _route(String? type) {
    final route = switch (type) {
      'stock_alert' || 'expiration_alert' => '/stock',
      _ => '/dashboard',
    };
    if (onNavigate == null) {
      pendingRoute = route;
    } else {
      onNavigate!(route);
    }
  }
}
