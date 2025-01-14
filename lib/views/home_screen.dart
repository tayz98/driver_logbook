import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:elogbook/models/driver.dart';
import 'package:elogbook/models/globals.dart';
import 'package:elogbook/models/trip_category.dart';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/objectbox.g.dart';
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
  late final StreamSubscription<String> _logSubscription;
  CustomBluetoothService? _customBluetoothService;
  SharedPreferences? _prefs;
  Timer? _reloadTimer;
  int? _newModeIndex;
  bool arePermissionsGranted = false;
  bool _isServiceRunning = false;
  Store? _store;
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
  void initState() {
    super.initState();
    _customBluetoothService = CustomBluetoothService();
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        _prefs = prefs;
      });
    });
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initForegroundService();
      await _requestAllPermissions();
      if (await FlutterForegroundTask.isRunningService == false &&
          arePermissionsGranted) {
        await _startBluetoothService();
        await _askIsolateForStoreReference();
      }
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    _reloadTimer?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _customBluetoothService = null;
    super.dispose();
  }

  Future<void> _askIsolateForStoreReference() async {
    bool isInitialized = false;

    // Listen for initialization status from the foreground isolate
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is Map && data['status'] == 'initialized') {
        isInitialized = true;
        debugPrint(
            '[Main] Received initialization status from foreground isolate');
      }
    });

    // Wait until initialization signal is received
    while (!isInitialized) {
      debugPrint('[Main] Waiting for foreground isolate to initialize...');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Send the command to request the store reference
    debugPrint('[Main] Sending get_store_reference command');
    FlutterForegroundTask.sendDataToTask({'command': 'get_store_reference'});
  }

  void _onReceiveTaskData(Object data) {
    debugPrint('[Main] Received data from background: $data');

    if (data is Map && data.containsKey('storeRef')) {
      final List<int> serializedStoreRef = data['storeRef'];
      final ByteData storeRef =
          ByteData.sublistView(Uint8List.fromList(serializedStoreRef));

      // Recreate the ObjectBox store using the deserialized reference
      _store = Store.fromReference(getObjectBoxModel(), storeRef);
      setState(() {});
      debugPrint('[Main] Recreated store from received reference');

      if (_store != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showUserInputDialog(context);
        });
      }
    } else {
      debugPrint('[Main] Received unsupported data: $data');
    }
  }

  void _initForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
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
        _showPermissionsGrantedDialog();
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
            'Einige Berechtigungen wurden verweigert. Bitte gewähren Sie alle Berechtigungen, um fortzufahren.',
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

  Future<ServiceRequestResult> _startBluetoothService() async {
    return FlutterForegroundTask.startService(
      notificationTitle: 'Bluetooth Foreground Service',
      notificationText: 'Scanning/Connecting to devices...',
      callback: startCallback,
    );
  }

  Future<ServiceRequestResult> _stopBluetoothService() async {
    return FlutterForegroundTask.stopService();
  }

  void startTaskAvailabilityListenerToSendData() {
    _reloadTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      _isServiceRunning = await FlutterForegroundTask.isRunningService;

      if (!arePermissionsGranted) {
        debugPrint("Permissions not granted. Waiting...");
        return; // Skip further checks if permissions are not granted.
      }

      if (_isServiceRunning) {
        // Send foundDeviceIds if available
        if (foundDeviceIds.isNotEmpty) {
          Future.delayed(const Duration(seconds: 1));
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
                  _store!.box<Driver>().put(driver);
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
          buttonBuilder('start BT service',
              onPressed: !_isServiceRunning
                  ? () {
                      _startBluetoothService();
                      setState(() {
                        _isServiceRunning = true;
                      });
                    }
                  : null),
          buttonBuilder('stop BT service',
              onPressed: _isServiceRunning
                  ? () {
                      _stopBluetoothService();
                      setState(() {
                        _isServiceRunning = false;
                      });
                    }
                  : null),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_store == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
        appBar: AppBar(
          title: const Text("NovaCorp - Fahrtenbuch"),
        ),
        body: Column(
          children: [
            //if (driver != null) buildTripDetails(context, trip, driver),
            //const Spacer(),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                // crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                  ElevatedButton(
                      onPressed: () => _reloadTimer == null
                          ? startTaskAvailabilityListenerToSendData()
                          : null,
                      child: const Text("Start Task Availability Listener")),
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
              ScanDevicesButton(
                onScan: () => _customBluetoothService!.scanForDevices(),
              ),
              const SizedBox(height: 8),
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
