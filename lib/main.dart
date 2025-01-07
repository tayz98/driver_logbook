import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/objectbox.g.dart';

import 'package:elogbook/views/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:elogbook/providers/providers.dart';
import 'package:path_provider/path_provider.dart'; // Aggregate all providers

final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

const MethodChannel platform =
    MethodChannel('dexterx.dev/flutter_local_notifications_example');

const String portName = 'notification_send_port';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeNotifications();

  requestNotificationPermission();
  final appDocDir = await getApplicationDocumentsDirectory();
  final store = openStore(directory: appDocDir.path);

  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MyApp()));
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
