import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'central.dart';

/// FCM registration for the passenger app. Aircraft WebSockets remain the
/// low-latency channel in flight; FCM covers booking/background updates.
class PushNotifications {
  PushNotifications._();
  static final instance = PushNotifications._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  String? _token;
  CentralClient? _client;
  String? _deviceId;
  bool _started = false;

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      settings: const InitializationSettings(android: android),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    const channel = AndroidNotificationChannel(
      'hashi_updates',
      'Hashi updates',
      description: 'Booking and cabin communication updates',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    _token = await _messaging.getToken();
    if (kDebugMode) debugPrint('HASHI FCM TOKEN: $_token');
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _token = token;
      unawaited(_registerIfReady());
    });
    unawaited(_registerIfReady());
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      id: message.hashCode,
      title: notification.title ?? 'Hashi update',
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'hashi_updates',
          'Hashi updates',
          channelDescription: 'Booking and cabin communication updates',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> register(CentralClient client, String deviceId) async {
    _client = client;
    _deviceId = deviceId;
    await _registerIfReady();
  }

  Future<void> _registerIfReady() async {
    final token = _token;
    final client = _client;
    final deviceId = _deviceId;
    if (token == null ||
        client == null ||
        client.token == null ||
        deviceId == null)
      return;
    try {
      await client.registerPushDevice(deviceId: deviceId, token: token);
    } on CentralException {
      // Registration is best-effort; offline-first behavior continues.
    }
  }
}
