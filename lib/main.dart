import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/objectbox.dart';
import 'package:elogbook/providers/providers.dart';
import 'package:elogbook/services/log_service.dart';
import 'package:elogbook/views/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

const MethodChannel platform =
    MethodChannel('dexterx.dev/flutter_local_notifications_example');

const String portName = 'notification_send_port';

late ObjectBox objectbox;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  Intl.defaultLocale = 'de_DE';
  objectbox = await ObjectBox.create();
  await LogService.initializeLogFile();
  await initializeNotifications();

  // requestNotificationPermission();

  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(ProviderScope(overrides: [
    storeProvider.overrideWithValue(objectbox.store),
  ], child: const MyApp()));
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
