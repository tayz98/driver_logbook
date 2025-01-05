// notification_service.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Streams can be kept here if you still need them globally.
final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

/// If you handle background taps, you can still place the callback here.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // This is called when a notification is tapped in the background/terminated state.
  debugPrint(
      'Notification action tapped: ${notificationResponse.actionId} with payload: ${notificationResponse.payload}');
}

/// Call this from main.dart or wherever you initialize your app.
Future<void> initializeNotifications() async {
  const AndroidInitializationSettings androidInitializationSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  // If you need iOS/MacOS settings:
  const DarwinInitializationSettings iosInitializationSettings =
      DarwinInitializationSettings();

  // Combine all settings:
  const InitializationSettings initializationSettings = InitializationSettings(
    android: androidInitializationSettings,
    iOS: iosInitializationSettings,
    macOS: iosInitializationSettings,
    // add more platforms (Linux, Windows) if needed
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: selectNotificationStream.add,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
}

/// Request notification permissions for both Android and iOS
Future<void> requestNotificationPermission() async {
  // Request permission on Android 13+
  if (Platform.isAndroid) {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
  }

  if (Platform.isIOS) {
    final bool? result = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    debugPrint('iOS Permission Granted: $result');
  }
}

/// Example function to show a notification. You can add more as needed.
Future<void> showBasicNotification({
  required String title,
  required String body,
  String? payload,
}) async {
  const AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    'basic_channel_id',
    'Basic Notifications',
    channelDescription: 'Channel for basic notifications',
    importance: Importance.max,
    priority: Priority.high,
  );

  const DarwinNotificationDetails iosNotificationDetails =
      DarwinNotificationDetails();

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidNotificationDetails,
    iOS: iosNotificationDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    0, // ID of the notification
    title,
    body,
    notificationDetails,
    payload: payload,
  );
}
