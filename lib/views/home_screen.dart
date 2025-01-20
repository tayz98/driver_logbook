import 'dart:async';
import 'package:elogbook/models/globals.dart';
import 'package:elogbook/models/trip_category.dart';
import 'package:elogbook/objectbox.dart';
import 'package:elogbook/views/settings_screen.dart';
import 'package:elogbook/widgets/choose_trip_mode_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:elogbook/services/custom_bluetooth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  // variables:
  CustomBluetoothService? _customBluetoothService;
  final StreamController<dynamic> _userDataStreamController =
      StreamController.broadcast();
  Stream<dynamic> get userDataStream => _userDataStreamController.stream;
  SharedPreferences? _prefs;
  int? _newModeIndex;

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
    _startListeningToChangesAndRedirectToTask();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await requestAllPermissions(context);
      initForegroundService();
      // start the background service automatically on startup
      if (await FlutterForegroundTask.isRunningService == false &&
          arePermissionsGranted) {
        await startBluetoothService();
      }
      // Check if service is running and set the state accordingly
      if (await FlutterForegroundTask.isRunningService &&
          arePermissionsGranted) {}
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _customBluetoothService = null;
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
    _userDataStreamController.stream.listen((data) async {
      if (!arePermissionsGranted) {
        debugPrint("Permissions not granted. Waiting...");
        return;
      }

      if (await isServiceRunning == false) {
        debugPrint("Task is not running. Waiting...");
        return;
      }
      FlutterForegroundTask.sendDataToTask(data);
      debugPrint("Data sent to task: $data");
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
                  if (await isServiceRunning == false) {
                    if (context.mounted) {
                      _showServiceNotRunningError(context);
                    }
                    return;
                  }
                  setState(() {
                    _newModeIndex = newMode.index;
                  });
                  _prefs?.setInt('tripCategory2', _newModeIndex!) ?? 0;
                  _userDataStreamController.add(_newModeIndex);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
