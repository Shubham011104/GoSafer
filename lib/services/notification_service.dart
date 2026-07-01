import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static final AuthService _authService = AuthService();

  // Observable for any active rescue data received via notification
  static final ValueNotifier<Map<String, dynamic>?> activeRescue = ValueNotifier(null);
  
  // Observable for status updates (e.g. "Someone is on their way")
  static final ValueNotifier<String?> statusUpdate = ValueNotifier(null);

  static Future<void> initialize() async {
    // 1. Request Permissions (iOS/Android 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permissions');
    }

    // 2. Setup Local Notifications for Foreground
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          try {
            final Map<String, dynamic> data = jsonDecode(details.payload!);
            _handleNotificationData(data);
          } catch (e) {
            debugPrint('Error parsing notification payload: $e');
          }
        }
      },
    );

    // 4. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Received foreground message: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // 5. Handle Notification Taps (App in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // 6. Handle Terminated App State (Tap to open)
    FirebaseMessaging.instance.getInitialMessage().then(_handleMessage);

    // 7. Handle Token Refresh
    _fcm.onTokenRefresh.listen((newToken) {
      _authService.updateFcmToken(newToken);
    });

    // 8. Initial Token Sync (if already logged in)
    await syncToken();
  }

  static void _handleMessage(RemoteMessage? message) {
    if (message != null) {
      _handleNotificationData(message.data);
    }
  }

  static void _handleNotificationData(Map<String, dynamic> data) {
    if (data['type'] == 'SOS_ALERT') {
      activeRescue.value = {
        'victim_uid': data['victim_uid'],
        'latitude': double.parse(data['latitude'].toString()),
        'longitude': double.parse(data['longitude'].toString()),
        'caller_name': data['caller_name'],
      };
      debugPrint('Active Rescue Set for: ${data['caller_name']}');
    } else if (data['type'] == 'SOS_RESPONSE') {
      statusUpdate.value = "${data['responder_name']} is on their way!";
      // Reset after a short delay so it can be triggered again
      Future.delayed(const Duration(seconds: 5), () {
        statusUpdate.value = null;
      });
    }
  }

  /// Manually triggers a token sync to Firestore. Call this after login.
  static Future<void> syncToken() async {
    String? token = await _fcm.getToken();
    if (token != null) {
      debugPrint('Syncing FCM Token: $token');
      await _authService.updateFcmToken(token);
    }
  }

  static void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'sos_channel',
            'SOS Alerts',
            channelDescription: 'Emergency notifications for nearby users',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }
}
