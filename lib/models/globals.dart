import 'dart:io';

import 'package:driver_logbook/bluetooth_task_handler.dart';
import 'package:driver_logbook/notification_configuration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// services
// init the foreground service

void initForegroundService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'Dieser Kanal wird für den Vordergrunddienst verwendet.',
        onlyAlertOnce: false,
        playSound: false,
        enableVibration: true,
        showBadge: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        priority: NotificationPriority.MAX,
        channelImportance: NotificationChannelImportance.MAX),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(20000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

// start the bluetooth-telemetry service and show a notification
Future<ServiceRequestResult?> startBluetoothService() async {
  if (await FlutterForegroundTask.isRunningService) {
    debugPrint('Service is already running. Exiting the method.');
    return null;
  }

  try {
    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'NovaCorp Fahrtenbuch',
      notificationText:
          'Die Aufzeichnung von Fahrten kann jederzeit gestartet werden!',
      callback: startCallback,
      notificationInitialRoute: '/doesnotexist',
    );
    return result;
  } catch (e) {
    debugPrint('Failed to start the Bluetooth service: $e');
    rethrow;
  }
}

// stop the bluetooth-telemetry service
Future<ServiceRequestResult> stopBluetoothService() async {
  return FlutterForegroundTask.stopService();
}

// app data
List<String> foundDeviceIds = [];

// app flags
bool privateTripsAllowed = false;

bool permissionGrantedForThisSession = false;

// system permissions
final List<Permission> permissions = [
  // location related:
  Permission.location,
  Permission.locationAlways,
  Permission.locationWhenInUse,
  // notifications:
  Permission.notification,
  // bluetooth:
  Permission.bluetoothScan,
  Permission.bluetoothConnect,
  // background related:
  if (Platform.isAndroid) Permission.scheduleExactAlarm,
  if (Platform.isAndroid) Permission.ignoreBatteryOptimizations,
  if (Platform.isIOS) Permission.backgroundRefresh,
];

// request all permissions needed for the foreground service to work
Future<void> requestAllPermissions(BuildContext context) async {
  bool allGranted = true;

  try {
    for (var permission in permissions) {
      if (!await permission.isGranted) {
        final status = await permission.request();
        if (status != PermissionStatus.granted) {
          allGranted = false;
        }
      }
    }

    // additional notification permission
    await requestNotificationPermission();

    if (Platform.isAndroid || Platform.isIOS) {
      final bool notificationGranted = await checkNotificationPermission();
      if (!notificationGranted) {
        allGranted = false;
      }
    }

    if (allGranted) {
      if (context.mounted) _showPermissionsGrantedDialog(context);
    } else {
      if (context.mounted) _showPermissionsDeniedDialog(context);
    }
  } catch (e) {
    debugPrint('Error while requesting permissions: $e');
    allGranted = false;
    if (context.mounted) _showPermissionsDeniedDialog(context);
  } finally {
    if (allGranted) {
      permissionGrantedForThisSession = true;
      SharedPreferences.getInstance().then((prefs) {
        // remember permission state
        prefs.setBool('arePermissionsGranted', allGranted);
      });
    }
  }
}

void _showPermissionsDeniedDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Berechtigungen wurden verweigert'),
        content: const Text(
          'Die App benötigt alle Berechtigungen, um korrekt zu funktionieren. Bitte aktivieren Sie alle Berechtigungen in den System-Einstellungen.',
        ),
        actions: [
          TextButton(
            onPressed: () => {
              if (Navigator.canPop(context)) {Navigator.of(context).pop()}
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

void _showPermissionsGrantedDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Berechtigungen wurden gewährt'),
        content: const Text(
          'Alle Berechtigungen wurden gewährt. Die App ist nun bereit für die Aufzeichnung von Fahrten.',
        ),
        actions: [
          TextButton(
            onPressed: () => {
              if (Navigator.canPop(context)) {Navigator.of(context).pop()}
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
