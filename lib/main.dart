import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/objectbox.g.dart';
import 'package:elogbook/services/log_service.dart';

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
  await LogService.initializeLogFile();
  await initializeNotifications();

  requestNotificationPermission();
  final appDocDir = await getApplicationDocumentsDirectory();
  final store = await openStore(directory: appDocDir.path);

  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MyApp()));
}

class MyApp extends StatelessWidget with WidgetsBindingObserver {
  const MyApp({super.key});

  void initState() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

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
