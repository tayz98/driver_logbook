import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/views/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import "../services/custom_bluetooth_service.dart";

final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

const MethodChannel platform =
    MethodChannel('dexterx.dev/flutter_local_notifications_example');

const String portName = 'notification_send_port';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeNotifications();

  requestNotificationPermission();

  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  CustomBluetoothService customBluetoothService = CustomBluetoothService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elogbook',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const Home(),
    );
  }
}
