import 'dart:async';
import 'dart:io';
import 'package:driver_logbook/controllers/trip_controller.dart';
import 'package:driver_logbook/models/globals.dart';
import 'package:driver_logbook/models/telemetry_bus.dart';
import 'package:driver_logbook/models/telemetry_event.dart';
import 'package:driver_logbook/objectbox.dart';
import 'package:driver_logbook/utils/extra.dart';
import 'package:driver_logbook/utils/vehicle_utils.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:driver_logbook/services/elm327_service.dart';

// maybe write a separate task handler for ios
// if it is even possible to run a task like that on ios

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BluetoothTaskHandler());
}

class BluetoothTaskHandler extends TaskHandler {
  // storing:
  late SharedPreferences
      _prefs; // shared preferences for storing known remote ids and category index

  // Bluetooth related:
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription; // for handling connection states
  List<String> knownRemoteIds = []; // list of known remote ids to connect to
  StreamSubscription<List<int>>?
      _dataSubscription; // for obversing incoming data from elm327
  StreamSubscription<List<ScanResult>>?
      _scanResultsSubscription; //  for handling scan results
  late Guid targetService; // target service for scanning
  late String targetName; // target name for scanning
  Elm327Service?
      _elm327Service; // elm327 controller for handling elm327 commands

  // Timer:
  Timer? _scanTimer; // timer to scan for devices if disconnected

  // misc:
  int? _tripCategoryIndex; // index of the trip category

  // --------------------------------------------------------------------------
  // METHODS: TaskHandler
  // --------------------------------------------------------------------------

// initialize data, bluetooth and (time) when the task is started
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _initializeData(); // e.g. shared preferences, objectbox, etc.
    // _initializeTime(); // initialize time for date formatting
    await _initializeBluetooth(); // complete bluetooth initialization
    CustomLogger.i('Service successfully started');
  }

  /// only used for trasmitting trips to the remote server
  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (TripController().isTripInProgress) {
      CustomLogger.d("Trip in progress, not transmitting");
      return;
    }
    syncTrips();
  }

  /// only used for receiving data from the main app (trip category and scanned remote ids)
  @override
  void onReceiveData(Object data) async {
    // the trip category and scan from the main app can be received here from the main app.
    CustomLogger.d(
        '[BluetoothTaskHandler] onReceiveData: $data type: ${data.runtimeType}');
    if (data is int) {
      // if data is int, it means it is the index of the trip category
      _tripCategoryIndex = data;
      if (_tripCategoryIndex != null &&
          _tripCategoryIndex! >= 0 &&
          _tripCategoryIndex! <= 2) {
        CustomLogger.d("New Trip category index: $_tripCategoryIndex");
        _prefs.setInt('tripCategory2', _tripCategoryIndex!);
      }
    } else if (data is List<dynamic>) {
      // if data is a list, it means it is a list of scanned remote ids from devices
      CustomLogger.d("Data is List<dynamic>");
      final newRemoteIds = data.cast<String>();
      for (var id in newRemoteIds) {
        if (knownRemoteIds.contains(id)) {
          CustomLogger.d("Remote id already known: $id");
          continue;
        } else {
          CustomLogger.d("New remote id received and added: $id");
          knownRemoteIds.add(id);
        }
      }
      _prefs.setStringList("knownRemoteIds", knownRemoteIds);
      if (knownRemoteIds.isEmpty) {
        CustomLogger.d("No known remote ids");
      }
      await _fetchAndConnectToDevices();
    } else {
      CustomLogger.w("Unknown data type received");
    }
  }

  /// NOT USED: Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    return;
  }

  /// NOT USED: Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    return;
  }

  /// NOT USED: Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    return;
  }

  /// Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    CustomLogger.d("Cleaning up data on destroy");
    _cancelAllStreams();
    _cancelAllTimer();
    _disposeElmService();
  }

  // --------------------------------------------------------------------------
  //  METHODS: Task related
  // --------------------------------------------------------------------------

  /// Update the notification text.
  void updateNotificationText(String newTitle, String newText) {
    FlutterForegroundTask.updateService(
      notificationTitle: newTitle,
      notificationText: newText,
    );
  }

  /// Make sure everything is cleaned up and reset when the task is destroyed.

  // cancel all streams
  void _cancelAllStreams() {
    _connectionStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _connectionStateSubscription = null;
    _scanResultsSubscription = null;
  }

  void _cancelAllTimer() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }
  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Bluetooth
  // --------------------------------------------------------------------------

  /// Initializes the Bluetooth functionality, sets up event listeners, and manages connections.
  ///
  /// This function performs the following tasks:
  /// - Configures `FlutterBluePlus` options for restoring state on iOS.
  /// - Ensures Bluetooth is enabled on Android devices.
  /// - Starts a periodic scan timer to discover nearby Bluetooth devices.
  /// - Listens for Bluetooth connection state changes and manages reconnections.
  /// - Updates and saves scan results to avoid redundant device scanning.
  /// - Fetches and connects to available Bluetooth devices.
  Future<void> _initializeBluetooth() async {
    FlutterBluePlus.setOptions(
        restoreState: true); // restoreState needed for iOS
    CustomLogger.d('[BluetoothTaskHandler] Initializing Bluetooth...');
    // Ensure Bluetooth is turned on for Android devices (not working on iOS)
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }

    /// Periodically scans for Bluetooth devices every 50 seconds.
    ///
    /// - In production, this should be increased to **100 seconds or more** to optimize battery usage.
    _scanTimer = Timer.periodic(const Duration(seconds: 50), (_) async {
      CustomLogger.d("scan timer started");
      await _scanDevices();
    });

    /// Listens for Bluetooth connection state changes and manages device connections accordingly.
    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      CustomLogger.i(
          "Event Device: ${event.device}, New Connection state: $event.connectionState");
      // On every connection state change, find the nearest device
      final tempDevice = await _findNearestDevice();
      if (event.connectionState == BluetoothConnectionState.connected) {
        // immediately setup the nearest connected device on connected state change
        if (tempDevice != null) {
          _setupConnectedDevice(tempDevice);
        }
      } else if (event.connectionState ==
          BluetoothConnectionState.disconnected) {
        // if the disconnected device was used for the elm327 service,
        // dispose wait for 5 seconds and check if the device is still disconnected
        if (event.device.remoteId == _elm327Service?.deviceId) {
          await Future.delayed(const Duration(seconds: 5), () async {
            if (event.device.isDisconnected) {
              // dispose service after 5 seconds
              await _disposeElmService();
            }
          });
        }

        /// If auto-connect is disabled (unexpected behavior), enable it again.
        ///
        /// - This is a **safety measure** to ensure devices can reconnect automatically after disconnection.
        if (!event.device.isAutoConnectEnabled) {
          event.device.connectAndUpdateStream();
          CustomLogger.d("Auto connect enabled again");
        }
        // if the disconnected device was not used for the elm327 service,
        // try to setup the nearest connected device
        if (tempDevice != null) {
          _setupConnectedDevice(tempDevice);
        }
      }
    });

    /// Listens for Bluetooth scan results and processes them.
    ///
    /// - Avoids adding duplicate devices by checking against `knownRemoteIds`.
    /// - Stores newly discovered device IDs in shared preferences.
    /// - Initiates connections to available devices.
    _scanResultsSubscription ??=
        FlutterBluePlus.onScanResults.listen((results) async {
      CustomLogger.i("Scan results: $results");
      if (results.isNotEmpty) {
        for (var result in results) {
          if (knownRemoteIds.contains(result.device.remoteId.str)) {
            CustomLogger.d(
                "Remote id already known: ${result.device.remoteId.str}");
            continue;
          } else {
            CustomLogger.d(
                "New remote id scanned and added: ${result.device.remoteId.str}");
            knownRemoteIds.add(result.device.remoteId.str);
            _prefs.setStringList("knownRemoteIds", knownRemoteIds);
          }
        }
        // fetch scanned device(s) to initiate new connections
        await _fetchAndConnectToDevices();
      }
    });
    CustomLogger.d(
        "Fetching and connecting to devices in _initializeBluetooth");
    // fetch for the first time in the initialization
    await _fetchAndConnectToDevices();
    CustomLogger.d("_initializeBluetooth completed");
  }

  Future<void> _disposeElmService() async {
    if (TripController().isTripInProgress) {
      CustomLogger.d("Trip in progress, not disposing controller");
      TelemetryEvent event = TelemetryEvent(voltage: 0.0);
      TelemetryBus().publish(event);
    }

    await _elm327Service?.dispose();
    _elm327Service = null;
  }

  // return the device with the best signal strength
  Future<BluetoothDevice?> _findNearestDevice() async {
    if (FlutterBluePlus.connectedDevices.isEmpty) {
      CustomLogger.d("No connected devices");
      return null;
    }
    final devices = FlutterBluePlus.connectedDevices;
    if (devices.length == 1) {
      return devices.first;
    }
    final deviceRssiMap = <BluetoothDevice, int>{};
    for (var device in devices) {
      final rssi = await device.readRssi();
      deviceRssiMap[device] = rssi;
    }

    final nearestDevice = deviceRssiMap.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
    return nearestDevice;
  }

  // discover characteristics and start elm327
  Future<void> _discoverCharacteristicsAndStartElm327(
      BluetoothDevice device) async {
    if (FlutterBluePlus.connectedDevices.isEmpty) {
      CustomLogger.d("Can't discover characteristics, no connected device");
      return;
    }
    CustomLogger.d("Discovering characteristics for service: $targetService");
    BluetoothCharacteristic? writeCharacteristic;
    BluetoothCharacteristic? notifyCharacteristic;
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            writeCharacteristic = c;
            CustomLogger.d("Write characteristic found: ${c.uuid}");
          }
          if (c.properties.notify) {
            notifyCharacteristic = c;
            await notifyCharacteristic.setNotifyValue(true);
            CustomLogger.d("Notify characteristic found: ${c.uuid}");
          }
        }
      }
    }

    if (writeCharacteristic != null && notifyCharacteristic != null) {
      _elm327Service = Elm327Service(
          writeCharacteristic: writeCharacteristic,
          notifyCharacteristic: notifyCharacteristic,
          device: device);
      CustomLogger.i(
          "Chraracteristics found, starting ELM327 with device: ${device.remoteId.str}");
      _dataSubscription = notifyCharacteristic.lastValueStream.listen((data) {
        CustomLogger.d("Received data!");
        _elm327Service!.handleReceivedData(data);
      });
      if (_dataSubscription != null) {
        device.cancelWhenDisconnected(_dataSubscription!, delayed: true);
      }
      final initialized = await _elm327Service?.initialize() ?? false;
      if (!initialized) {
        CustomLogger.e("ELM327 initialization failed");
        // if initialization failed, disconnect and set shared preference initializization status to false
        await _prefs.setBool(device.remoteId.str, false);
        device.disconnectAndUpdateStream();
      } else {
        CustomLogger.i("ELM327 successfully initialized");
        CustomLogger.d("Starting checking for voltage");
        await _elm327Service!.startVoltageTimer();
      }
    } else {
      CustomLogger.e("Characteristics not found, can't start ELM327");
    }
  }

  Future<void> _setupConnectedDevice(BluetoothDevice device) async {
    if (_elm327Service?.isTripInProgress == true) {
      // if a trip is in progress, don't set up a new connected device
      CustomLogger.d("Trip in progress, not setting up new connected device");
      return;
    } else if (_elm327Service?.isTripInProgress == false) {
      // if no trip is in progress, dispose the controller, to start a new one
      _disposeElmService();
    }

    CustomLogger.d("Setting up connected device: ${device.remoteId.str}");
    await _requestMtu(device);
    await _discoverCharacteristicsAndStartElm327(device);
  }

  Future<void> _requestMtu(BluetoothDevice device) async {
    try {
      CustomLogger.d("Requesting MTU...");
      await device.requestMtu(128, predelay: 0);
      CustomLogger.d("MTU after request: ${device.mtu}");
    } catch (e) {
      return;
    }
  }

  // create all necessary data
  Future<void> _initializeData() async {
    await dotenv.load(fileName: ".env");
    targetName = dotenv.get("TARGET_ADV_NAME", fallback: "");
    targetService = Guid(dotenv.get('TARGET_SERVICE', fallback: ''));
    CustomLogger.d('Initialized dotenv');

    CustomLogger.d('Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    CustomLogger.d('Initialized SharedPreferences');
    try {
      await ObjectBox.create();
      CustomLogger.d('Initialized ObjectBox');
    } catch (e) {
      CustomLogger.e('ObjectBox error: $e');
    }
    knownRemoteIds = _prefs.getStringList("knownRemoteIds") ?? [];
    CustomLogger.d('Initialized knownRemoteIds');
    await TripController.initialize();
    CustomLogger.d('Initialized TripController');
    await VehicleUtils.initializeVehicleModels();
    CustomLogger.d('Initialized VehicleModels');
  }

  // find new devices
  Future<void> _scanDevices() async {
    try {
      CustomLogger.d("Scanning for devices...");
      await FlutterBluePlus.startScan(
          withServices: [targetService],
          withNames: [targetName],
          timeout: const Duration(seconds: 2));
    } catch (e) {
      CustomLogger.e("Error in _scanDevices: $e");
      return;
    }
  }

  // auto connects to known or recently scanned devices
  Future<void> _fetchAndConnectToDevices() async {
    _prefs.reload(); // reload shared preferences if received from the main app
    CustomLogger.d("Fetching and connecting to devices...");
    CustomLogger.i("Known remote ids: $knownRemoteIds");
    if (knownRemoteIds.isEmpty) {
      CustomLogger.d("No known remote ids");
      return;
    }

    for (var id in knownRemoteIds) {
      try {
        final device = BluetoothDevice.fromId(id);
        await device.connectAndUpdateStream();
        CustomLogger.i("Starting auto connect to device: $id");
        break;
      } catch (e) {
        CustomLogger.e("Error in _fetchAndConnectToDevices: $e");
        return;
      }
    }
  }
}
