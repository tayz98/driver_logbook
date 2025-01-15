import 'dart:async';
import 'dart:io';
import 'package:elogbook/models/driver.dart';
import 'package:elogbook/models/globals.dart';
import 'package:elogbook/models/trip_category.dart';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/objectbox.dart';
import 'package:elogbook/widgets/check_permissions_button.dart';
import 'package:elogbook/widgets/choose_trip_mode_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:elogbook/widgets/scan_devices_button.dart';
import 'package:elogbook/bluetooth_task_handler.dart';
import 'package:elogbook/services/custom_bluetooth_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  //final List<String> _logs = [];
  //late final StreamSubscription<String> _logSubscription;
  CustomBluetoothService? _customBluetoothService;
  SharedPreferences? _prefs;
  Timer? _reloadTimer;
  int? _newModeIndex;
  bool arePermissionsGranted = false;
  bool _isServiceRunning = false;
  final List<Permission> _permissions = [
    Permission.location,
    Permission.locationAlways,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    if (Platform.isAndroid) Permission.scheduleExactAlarm,
    if (Platform.isAndroid) Permission.ignoreBatteryOptimizations,
    //Permission.backgroundRefresh, // TODO: check if this is needed
  ];

  @override
  initState() {
    super.initState();
    _customBluetoothService = CustomBluetoothService();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        _prefs = prefs;
      });
    });
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    sendAllDataPeriodicallyToTask();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initForegroundService();
      await _requestAllPermissions();
      // start the service automatically on startup
      if (await FlutterForegroundTask.isRunningService == false &&
          arePermissionsGranted) {
        await _startBluetoothService();
      }
      // Check if service is running and set the state accordingly
      if (await FlutterForegroundTask.isRunningService &&
          arePermissionsGranted) {
        setState(() {
          _isServiceRunning = true;
        });
      }
      // only show user registration dialog if no driver is registered
      if (ObjectBox.store.box<Driver>().isEmpty()) {
        if (mounted) {
          _showUserInputDialog(context);
        }
      }
    });
  }

  @override
  void dispose() {
    //_logSubscription.cancel();
    _reloadTimer?.cancel();
    _reloadTimer = null;
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _customBluetoothService = null;
    ObjectBox.store.close();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {}

  void _initForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'foreground_service',
          channelName: 'Foreground Service Notification',
          channelDescription:
              'Dieser Kanal wird für den Vordergrunddienst verwendet.',
          onlyAlertOnce: false,
          playSound: true,
          showBadge: true,
          priority: NotificationPriority.MAX,
          channelImportance: NotificationChannelImportance.MAX),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: true,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(4000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _requestAllPermissions() async {
    bool allGranted = true;

    try {
      for (var permission in _permissions) {
        if (!await permission.isGranted) {
          final status = await permission.request();
          if (status != PermissionStatus.granted) {
            allGranted = false;
          }
        }
      }

      await requestNotificationPermission();

      if (Platform.isAndroid || Platform.isIOS) {
        final bool notificationGranted = await checkNotificationPermission();
        if (!notificationGranted) {
          allGranted = false;
        }
      }

      if (allGranted) {
        //_showPermissionsGrantedDialog();
      } else {
        _showPermissionsDeniedDialog();
      }
    } catch (e) {
      debugPrint('Error while requesting permissions: $e');
      allGranted = false;
      _showPermissionsDeniedDialog();
    } finally {
      setState(() {
        arePermissionsGranted = allGranted;
      });
    }
  }

  void _showPermissionsDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Berechtigungen wurden verweigert'),
          content: const Text(
            'Einige Berechtigungen wurden verweigert. Die App funktioniert nicht ohne diese.',
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

  // TODO: find a way to implement this usefully
  void _showPermissionsGrantedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Berechtigungen wurden gewährt'),
          content: const Text(
            'Alle Berechtigungen wurden gewährt. Sie können jetzt fortfahren.',
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

  Future<ServiceRequestResult?> _startBluetoothService() async {
    if (_isServiceRunning) {
      debugPrint('Service is already running. Exiting the method.');
      return null;
    }
    setState(() {
      _isServiceRunning = true;
    });

    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'Vordergrunddienst läuft',
        notificationText:
            'Die Aufzeichnung von Fahrten kann jederzeit gestartet werden!',
        callback: startCallback,
      );
      return result;
    } catch (e) {
      debugPrint('Failed to start the Bluetooth service: $e');
      setState(() {
        _isServiceRunning = false;
      });
      rethrow;
    }
  }

  Future<ServiceRequestResult> _stopBluetoothService() async {
    setState(() {
      _isServiceRunning = false;
    });
    return FlutterForegroundTask.stopService();
  }

  // TODO: think if this needs to be reworked
  void sendAllDataPeriodicallyToTask() {
    // send every 2 seconds device ids and mode index to the service
    _reloadTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      _isServiceRunning = await FlutterForegroundTask.isRunningService;

      if (!arePermissionsGranted) {
        debugPrint("Permissions not granted. Waiting...");
        return; // Skip further checks if permissions are not granted.
      }

      if (_isServiceRunning) {
        // Send foundDeviceIds if available
        if (foundDeviceIds.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500));
          FlutterForegroundTask.sendDataToTask(foundDeviceIds);
          debugPrint(
              "Data sent to task: $foundDeviceIds data type: ${foundDeviceIds.runtimeType} ");
        }

        if (_newModeIndex != null) {
          Future.delayed(const Duration(seconds: 1));
          FlutterForegroundTask.sendDataToTask(_newModeIndex!);
          debugPrint("Data sent to task: $_newModeIndex");
          // Reset newModeIndex after sending
        }
      } else {
        debugPrint("Task is not running. Waiting...");
      }
    });
  }

  void _showUserInputDialog(BuildContext context) {
    // create a dialog to input user data
    // and save it to the database
    String firstName = '';
    String lastName = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Registrierung'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Vorname'),
                onChanged: (value) {
                  firstName = value;
                },
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'Nachname'),
                onChanged: (value) {
                  lastName = value;
                },
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1.5,
                ),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                  (states) {
                    if (states.contains(WidgetState.pressed)) {
                      return Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1);
                    }
                    return Theme.of(context).colorScheme.surface;
                  },
                ),
              ),
              onPressed: () async {
                if (firstName.isNotEmpty && lastName.isNotEmpty) {
                  final driver = Driver(name: firstName, surname: lastName);
                  ObjectBox.store.box<Driver>().put(driver);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Bitte alle Felder ausfüllen')),
                  );
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServiceControlButtons() {
    // buttons for services, TODO: move to separate page
    buttonBuilder(String text, {VoidCallback? onPressed}) {
      return ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buttonBuilder('Start BT-Dienst',
              onPressed: !_isServiceRunning
                  ? () {
                      _startBluetoothService();
                    }
                  : null),
          buttonBuilder('Stop BT-Dienst',
              onPressed: _isServiceRunning
                  ? () {
                      _stopBluetoothService();
                    }
                  : null),
        ],
      ),
    );
  }

  // thoughts: tripmodebuttons centered, and settings wheel on one corner
  // add a settings page which includes things like permissions and service control
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("NovaCorp - Fahrtenbuch"),
        ),
        body: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                // crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // TODO: make bigger and centered
                  ChooseTripModeButtons(
                    initialMode: TripCategory
                        .values[_prefs?.getInt('tripCategory2') ?? 0],
                    onModeChanged: (newMode) {
                      setState(() {
                        _newModeIndex = newMode.index;
                      });
                      _prefs?.setInt('tripCategory2', _newModeIndex!) ?? 0;
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildServiceControlButtons(),
              //: Container(),
              //const Center(child: Text("No logs yet.")),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // TODO: move to separate page
              ScanDevicesButton(
                onScan: () => _customBluetoothService!.scanForDevices(),
              ),
              const SizedBox(height: 8),
              // TODO: move to separate page
              PermissionsButton(
                permissionGranted: arePermissionsGranted,
                onPermissionStatusChanged: (bool granted) {
                  setState(() {
                    arePermissionsGranted = granted;
                  });
                },
              ),
            ],
          ),
        ));
  }
}
