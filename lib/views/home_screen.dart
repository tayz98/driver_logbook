import 'dart:async';
import 'dart:io';
import 'package:driver_logbook/models/globals.dart';
import 'package:driver_logbook/models/trip_category.dart';
import 'package:driver_logbook/objectbox.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:driver_logbook/views/settings_screen.dart';
import 'package:driver_logbook/widgets/choose_trip_mode_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:driver_logbook/services/custom_bluetooth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  // variables:
  CustomBluetoothService? _customBluetoothService; // used for scanning
  final StreamController<dynamic> _userDataStreamController =
      StreamController.broadcast(); // used for sending data to the service
  Stream<dynamic> get userDataStream => _userDataStreamController.stream;
  SharedPreferences? _prefs; // used for storing persistent data
  int? _newModeIndex; // current mode index (trip category)

  @override
  initState() {
    super.initState();
    // initialize database, services and permissions
    ObjectBox.create();
    _customBluetoothService = CustomBluetoothService();
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
    });
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // final areGranted = _prefs?.getBool('arePermissionsGranted') ?? false;
      // if (!areGranted && Platform.isAndroid) {
      //   // prevent requesting permissions if they are already granted
      //   await requestAllPermissions(context);
      // }
      if (Platform.isAndroid) {
        initForegroundService();
      }
      final permissionsGranted = await requestAllPermissions(context);

      // start the background service automatically on startup
      if (await FlutterForegroundTask.isRunningService == false &&
          permissionsGranted) {
        await startBluetoothService();
      }
      if (!permissionsGranted) {
        if (mounted) {
          showPermissionsDeniedDialog(context);
        }
      }
      await syncTrips();
      // Check if service is running and set the state accordingly
      // if (await FlutterForegroundTask.isRunningService && permissionsGranted) {}
    });
    _startListeningToChangesAndRedirectToTask();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    ObjectBox.store.close();
    _userDataStreamController.close();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    // handle data received from the task
    // right now not needed
  }

  // sends index of category or remoteIds of BT-Devices to the service
  void _startListeningToChangesAndRedirectToTask() {
    if (Platform.isIOS) {
      CustomLogger.d('iOS not working with foreground service');
      return;
    }
    _userDataStreamController.stream.listen((data) async {
      if (_prefs!.getBool('arePermissionsGranted') == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Berechtigungen fehlen.',
              ),
            ),
          );
        }
        return;
      }

      if (false == await FlutterForegroundTask.isRunningService) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dienst nicht gestartet.',
              ),
            ),
          );
        }
        return;
      }
      FlutterForegroundTask.sendDataToTask(data);
      CustomLogger.d("Data sent to task: $data");
    });
  }

  void _showServiceNotRunningError(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Fehler'),
          content: const Text(
            'Der Bluetooth-Dienst ist nicht gestartet. Bitte starten Sie zuerst den Dienst, und wählen Sie den Modus dann noch mal aus.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("NovaCorp - Fahrtenbuch"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) {
                return Settings(
                  onScan: () => _customBluetoothService!.scanForDevices(),
                );
              }));
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Fahrtkategorie:',
                style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20.0),
              ChooseTripModeButtons(
                initialMode:
                    TripCategory.values[_prefs?.getInt('tripCategory2') ?? 0],
                onModeChanged: (newMode) async {
                  if (false == await FlutterForegroundTask.isRunningService &&
                      Platform.isAndroid) {
                    if (context.mounted) {
                      _showServiceNotRunningError(context);
                    }
                    return;
                  }
                  setState(() {
                    _newModeIndex = newMode.index;
                  });
                  _prefs?.setInt('tripCategory2', _newModeIndex!) ?? 0;
                  if (Platform.isAndroid) {
                    _userDataStreamController.add(_newModeIndex);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
