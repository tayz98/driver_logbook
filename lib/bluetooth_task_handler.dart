import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:elogbook/controllers/trip_controller.dart';
import 'package:elogbook/models/driver.dart';
import 'package:elogbook/models/trip.dart';
import 'package:elogbook/models/trip_location.dart';
import 'package:elogbook/models/trip_status.dart';
import 'package:elogbook/objectbox.dart';
import 'package:elogbook/objectbox.g.dart';
import 'package:elogbook/services/gps_service.dart';
import 'package:elogbook/utils/extra.dart';
import 'package:elogbook/utils/vehicle_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BluetoothTaskHandler());
}

class BluetoothTaskHandler extends TaskHandler {
  // Data
  late Store _objectBox;
  TripController? _tripController;
  late SharedPreferences _prefs;

  // Bluetooth
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastConnectedDevice;
  final List<BluetoothDevice> _knownDevices = [];
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothConnectionState? _connectionState;
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription;
  StreamSubscription<int>? _rssiStreamSubscription;
  final int _disconnectRssiThreshold = -150;
  //final int _rssiTresholdForElm327Service = -70;
  List<String> knownRemoteIds = [];
  Timer? _disconnectTimer;
  DateTime _lastMileageResponseTime = DateTime.now();
  int? tripCategoryIndex;
  bool wasDataChecked = false;

  // misc
  GpsService? _gpsService;
  final Completer<void> _initializationCompleter = Completer<void>();

  String? _vehicleVin;
  int? _vehicleMileage;
  Timer? mileageSendCommandTimer;
  TripLocation _tempLocation = TripLocation(
      street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
  String _responseBuffer = '';
  bool isElm327Initialized = false;
  final String skodaMileageCommand = "2210E01";
  final String vinCommand = "0902";
  final StreamController<void> _mileageResponseController =
      StreamController<void>.broadcast();

  // --------------------------------------------------------------------------
  // PUBLIC METHODS: TaskHandler
  // --------------------------------------------------------------------------

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BluetoothTaskHandler] onStart: ${starter.name}');
    await _initializeData();
    await _initializeBluetooth();

    // listen for mileage response and update the last response time
    _mileageResponseController.stream.listen((_) {
      _lastMileageResponseTime = DateTime.now();
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    try {
      // wait for initialization to complete before proceeding
      await _initializationCompleter.future;
      debugPrint(ObjectBox.store.box<Trip>().getAll().toString());
      debugPrint(ObjectBox.store.box<Driver>().getAll().toString());
      if (ObjectBox.store.box<Driver>().isEmpty()) {
        debugPrint("Driver not found");
        // TODO: either create a new driver or show a notification
        return;
      }

      // debug
      debugPrint('[BluetoothTaskHandler] onRepeatEvent: $timestamp');
      debugPrint('[BluetoothTaskHandler] Connection state: $_connectionState');
      debugPrint(
          '[BluetoothTaskHandler] Trip: ${_tripController?.currentTrip}');
      debugPrint('Known remote ids: $knownRemoteIds');

      if (isElm327Initialized) {
        // only start telemetry collection if the elm327 controller is initialized
        if (_tripController?.currentTrip != null &&
            _tripController?.currentTrip?.tripStatusEnum ==
                TripStatus.inProgress) {
          final difference =
              DateTime.now().difference(_lastMileageResponseTime).inSeconds;
          if (difference > 15) {
            debugPrint("No response from ELM327 for 15 seconds..Ending trip");
            _endTelemetryCollection();
            return;
          }
        }
        _tripController ??= TripController(ObjectBox.store, _prefs);
        _gpsService ??= GpsService();
        await _sendCommand(skodaMileageCommand); // query mileage continuously
        await Future.delayed(
            const Duration(seconds: 1)); // wait for the response
        if (!wasDataChecked) {
          await _checkData();
        } else {
          await _startOrUpdateTrip();
        }
        // if the elm327 has not responded and therefore the initialization has been set to false
        // but the device is still connected and the driver  plans to start a consecutive trip
        // the initialization has to be done again, maybe add another boolean like hasTripEnded for more robustness
      } else if (_connectedDevice != null && !isElm327Initialized) {
        await _initializeElm327();
      }
    } catch (e, stackTrace) {
      debugPrint('Error in onRepeatEvent: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void onReceiveData(Object data) async {
    debugPrint(
        '[BluetoothTaskHandler] onReceiveData: $data type: ${data.runtimeType}');

    // only the trip category index is received as int from the main app
    if (data is int) {
      tripCategoryIndex = data;
      if (tripCategoryIndex != null &&
          tripCategoryIndex! >= 0 &&
          tripCategoryIndex! <= 2) {
        debugPrint("New Trip category index: $tripCategoryIndex");
        _prefs.setInt('tripCategory2', tripCategoryIndex!);
      }
      // TODO: check which type is needed to handle following data
    } else if (data is List<dynamic>) {
      debugPrint("Data is List<dynamic>");
      final newRemoteIds = data.cast<String>();
      for (var id in newRemoteIds) {
        if (knownRemoteIds.contains(id)) {
          debugPrint("Remote id already known: $id");
          continue;
        } else {
          debugPrint("New remote id added: $id");
          knownRemoteIds.add(id);
        }
      }
      _prefs.setStringList("knownRemoteIds", knownRemoteIds);
      if (knownRemoteIds.isEmpty) {
        debugPrint('[BluetoothTaskHandler] No known remote ids');
      }
      await _fetchDevicesAndConnect();
    } else if (data is List<String>) {
      debugPrint("Data is List<String>");
      final newRemoteIds = data.cast<String>();
      for (var id in newRemoteIds) {
        if (knownRemoteIds.contains(id)) {
          debugPrint("Remote id already known: $id");
          continue;
        } else {
          debugPrint("New remote id added: $id");
          knownRemoteIds.add(id);
        }
      }
      _prefs.setStringList("knownRemoteIds", knownRemoteIds);
      if (knownRemoteIds.isEmpty) {
        debugPrint('[BluetoothTaskHandler] No known remote ids');
      }
      await _fetchDevicesAndConnect();
    } else if (data is String) {
      debugPrint("Data is String");
      final newRemoteId = data;
      if (knownRemoteIds.contains(newRemoteId)) {
        debugPrint("Remote id already known: $newRemoteId");
      } else {
        debugPrint("New remote id added: $newRemoteId");
        knownRemoteIds.add(newRemoteId);
        _prefs.setStringList("knownRemoteIds", knownRemoteIds);
        await _fetchDevicesAndConnect();
      }
    } else {
      debugPrint("Data is not recognized");
    }
  }

  /// Called when the notification button is pressed.
  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[BluetoothTaskHandler] onNotificationButtonPressed: $id');
    // Handle any notification button actions here.
  }

  /// Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    debugPrint('[BluetoothTaskHandler] onNotificationPressed');
  }

  /// Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    debugPrint('[BluetoothTaskHandler] onNotificationDismissed');
  }

  /// Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    if (_connectedDevice != null) {
      await _disposeConnection(_connectedDevice!);
    }
    // if any trip was in progress, cancel it
    if (Platform.isAndroid && _tripController?.currentTrip != null) {
      _tripController!.cancelTrip(_tempLocation);
    }
    // on ios: maybe pause and resume, because tasks could be destroyed more often
    _objectBox.close();
    _tripController = null;
    debugPrint('[BluetoothTaskHandler] onDestroy');
    // Cleanup resources
  }

  // --------------------------------------------------------------------------
  //  METHODS: Task related
  // --------------------------------------------------------------------------

  void updateNotificationText(String newTitle, String newText) {
    FlutterForegroundTask.updateService(
      notificationTitle: newTitle,
      notificationText: newText,
    );
  }

  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Bluetooth
  // --------------------------------------------------------------------------

  Future<void> _initializeBluetooth() async {
    debugPrint('[BluetoothTaskHandler] Initializing Bluetooth...');
    FlutterBluePlus.setOptions(restoreState: true);
    //FlutterBluePlus.setLogLevel(LogLevel.verbose);

    // handle device when the connection state changes
    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen(
      (event) async {
        _connectionState = event.connectionState;
        if (_connectionState == BluetoothConnectionState.connected) {
          _connectedDevice = event.device;
        }
        // read rssi, disconnect if device is too far away
        final int currentRssi = await _connectedDevice!.readRssi();
        debugPrint(
            '[BluetoothTaskHandler] Device ${_connectedDevice!.remoteId.str} RSSI: $currentRssi');
        if (currentRssi < _disconnectRssiThreshold) {
          debugPrint(
              '[BluetoothTaskHandler] Disconnecting device due to low RSSI: $currentRssi');
          await _disposeConnection(_connectedDevice!);
        }
        // request MTU and discover characteristics if connected
        await _requestMtu(_connectedDevice!);
        await _discoverCharacteristics(_connectedDevice!);
        // check rssi continously to disconnect the device if it is too far away
        _trackRssi(
            dev: _connectedDevice!, interval: const Duration(seconds: 5));
        if (_connectionState == BluetoothConnectionState.disconnected) {
          if (_connectedDevice != null) {
            await _disposeConnection(_connectedDevice!);
          }
          // needed because when disconnect() is used with the autoConnect parameter
          // it doesn't reconnect automatically anymore
          Future.delayed(const Duration(seconds: 10), () {
            // longer delay to prevent reconnecting to the same device if other devices are available
            _lastConnectedDevice?.connectAndUpdateStream();
          });
        }
      },
    );
    await _fetchDevicesAndConnect();
  }

  Stream<int> _rssiStream(BluetoothDevice device, Duration interval) async* {
    while (true) {
      try {
        int rssiValue = await device.readRssi();
        yield rssiValue;
      } catch (e) {
        break;
      }
      await Future.delayed(interval);
    }
  }

  void _trackRssi({required BluetoothDevice dev, required Duration interval}) {
    _rssiStreamSubscription = _rssiStream(dev, interval).listen((rssiValue) {
      if (rssiValue < _disconnectRssiThreshold) {
        _disconnectTimer ??= Timer(const Duration(seconds: 5), () {
          _disconnectTimer = null;
          _connectionState = BluetoothConnectionState.disconnected;
        });
      } else {
        if (_disconnectTimer != null) {
          _disconnectTimer?.cancel();
          _disconnectTimer = null;
        }
      }
    }, onError: (error) {
      _rssiStreamSubscription?.cancel();
    });
  }

  Future<void> _discoverCharacteristics(BluetoothDevice dev) async {
    final Guid targetService = Guid("0000fff0-0000-1000-8000-00805f9b34fb");
    List<BluetoothService> services = await dev.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            _writeCharacteristic = c;
          }
          if (c.properties.notify) {
            _notifyCharacteristic = c;
          }
        }
      }
    }

    if (_writeCharacteristic != null && _notifyCharacteristic != null) {
      await _notifyCharacteristic!.setNotifyValue(true);
      // only initialize elm327 if the needed characteristics are found
      // and listen for incoming data
      await _initializeElm327();
      _notifyCharacteristic!.lastValueStream.listen(handleReceivedData);
    }
  }

  Future<void> _requestMtu(BluetoothDevice dev) async {
    try {
      await dev.requestMtu(128, predelay: 0);
      debugPrint("[BluetoothTaskHandler] Device MTU after request: ${dev.mtu}");
    } catch (e) {
      return;
    }
  }

  Future<void> _disposeConnection(BluetoothDevice dev) async {
    isElm327Initialized = false;
    debugPrint(
        '[BluetoothTaskHandler] Disconnecting device: ${_connectedDevice!.remoteId.str}');
    _lastConnectedDevice = dev;
    await _connectedDevice?.disconnectAndUpdateStream();
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    await _rssiStreamSubscription?.cancel();
    _rssiStreamSubscription = null;
  }

  Future<void> _initializeData() async {
    debugPrint('[BluetoothTaskHandler] Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    try {
      await ObjectBox.create();
    } catch (e) {
      debugPrint('[BluetoothTaskHandler] ObjectBox error: $e');
    }
    debugPrint('[BluetoothTaskHandler] Initialized ObjectBox');
    _tripController = TripController(ObjectBox.store, _prefs);
    debugPrint('[BluetoothTaskHandler] Initialized SharedPreferences');
    knownRemoteIds = _prefs.getStringList("knownRemoteIds") ?? [];
    debugPrint('[BluetoothTaskHandler] Initialized knownRemoteIds');
    _initializationCompleter.complete();
    debugPrint('[BluetoothTaskHandler] Initialized data');
    // debugPrint(
    //     "initializiation: ${_objectBox.store.box<Trip>().getAll().toString()}");
    FlutterForegroundTask.sendDataToMain({'status': 'initialized'});
  }

  Future<void> _fetchDevicesAndConnect() async {
    debugPrint('[BluetoothTaskHandler] Fetching devices and connecting...');
    debugPrint("knownRemoteIds: $knownRemoteIds");
    if (knownRemoteIds.isEmpty) {
      debugPrint('[BluetoothTaskHandler] No known devices to connect to.');
      return;
    }
    try {
      for (var id in knownRemoteIds) {
        // skip already fetched devices
        if (_knownDevices.any((device) => device.remoteId.str == id)) {
          continue;
        } else {
          try {
            final device = BluetoothDevice.fromId(id);
            _knownDevices.add(device);
            await device.connectAndUpdateStream();
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint('[BluetoothTaskHandler] Connect error: $e');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[BluetoothTaskHandler] Fetch devices error: $e');
      return;
    }
  }

  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Elm327
  // --------------------------------------------------------------------------

  Future<void> _initializeElm327() async {
    debugPrint("Initializing ELM327");
    List<String> initCommands = [
      "ATZ", // Reset ELM327
      "ATE0", // Echo Off
      "ATL0", // Linefeeds Offr
      "ATS0", // Spaces Off
      "ATH1", // Headers On
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];
    for (String cmd in initCommands) {
      await _sendCommand(cmd);
      await Future.delayed(const Duration(
          milliseconds: 2500)); // wait for every command to process
    }
    isElm327Initialized = true;
  }

  // send command to elm327
  Future<void> _sendCommand(String command) async {
    debugPrint("Sending command: $command");
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await _writeCharacteristic?.write(bytes, withoutResponse: true);
    } catch (e) {
      debugPrint("Error in _sendCommand: $e");
    }
  }

  // check if VIN and mileage are valid
  Future<bool> _checkData() async {
    debugPrint("Checking data...");
    bool vin = await _checkVin();
    bool mileage =
        _checkMileageOfSkoda(); // mileage already known by now, that's why it's not awaited
    if (vin && mileage) {
      wasDataChecked = true;
    }
    return vin && mileage;
  }

  // check if VIN is valid
  Future<bool> _checkVin() async {
    if (_vehicleVin == null) {
      await _sendCommand(vinCommand);
      await Future.delayed(const Duration(milliseconds: 2500));
      // wait for the response (could take longer then usual)
    }

    if (_vehicleVin?.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      if (vinRegex.hasMatch(_vehicleVin!)) {
        return true;
      }
    }
    return false;
  }

  // check if mileage is valid
  bool _checkMileageOfSkoda() {
    if (_vehicleMileage != null &&
        _vehicleMileage! >= 0 &&
        _vehicleMileage! <= 2000000) {
      return true;
    }
    return false;
  }

  // manage incoming data from elm327
  void handleReceivedData(List<int> data) {
    // decode it and add it to the buffer because responses can be split into multiple parts
    String incomingData = utf8.decode(data);
    _responseBuffer += incomingData;
    int endIndex = _responseBuffer.indexOf(">"); // ">" is the end of a response
    while (endIndex != -1) {
      String completeResponse = _responseBuffer.substring(0, endIndex).trim();
      _responseBuffer = _responseBuffer.substring(endIndex + 1);
      _processCompleteResponse(completeResponse);
      endIndex = _responseBuffer.indexOf(">");
    }
  }

  // process the complete response from elm327
  void _processCompleteResponse(String response) {
    // remove all unnecessary characters or words
    String cleanedResponse = response
        .trim()
        .replaceAll("]", "")
        .replaceAll("[", "")
        .replaceAll(">", "")
        .replaceAll("<", "")
        .replaceAll(":", "")
        .replaceAll(".", "")
        .replaceAll(" ", "")
        .replaceAll("\u00A0", "")
        .replaceAll(RegExp(r"\s+"), "")
        .replaceAll("SEARCHING", "")
        .replaceAll("STOPPED", "")
        //.replaceAll("ELM327V15", "")
        .replaceAll("NODATA", "")
        .replaceAll("TIMEOUT", "")
        .replaceAll("CANERROR", "")
        .replaceAll("OK", "");

    if (cleanedResponse.isEmpty) return; // unsolicited response, ignore it
    // every mileage response starts with 6210
    if (cleanedResponse.contains("6210")) {
      // startsWith doesn't work for some reason, that's why contains is used
      _handleResponseToSkodaMileageCommand(cleanedResponse);
    }

    // 7E8 is the device id, 10 is the FF,
    //14 is the length of the response (20 bytes),
    //49 is the answer to the mode 09
    if (cleanedResponse.contains("7E8101449")) {
      // startsWith doesn't work here too
      _handleResponseToVINCommand(cleanedResponse);
    }
  }

  void _handleResponseToVINCommand(String response) {
    _vehicleVin = VehicleUtils.getVehicleVin(response);
  }

  void _handleResponseToSkodaMileageCommand(String response) {
    _vehicleMileage = VehicleUtils.getVehicleKmOfSkoda(response);
    _mileageResponseController.add(null);
  }

  Future<void> _startOrUpdateTrip() async {
    try {
      if (_tripController!.currentTrip == null) {
        try {
          final position = await _gpsService!.currentPosition;
          debugPrint("Position: $position");
          _tempLocation = await _gpsService!.getLocationFromPosition(position);
        } catch (e) {
          debugPrint("Error in _updateTrip: $e");
          _tempLocation = TripLocation(
              street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
        }
        debugPrint("Location: $_tempLocation");
        debugPrint("Creating new trip...");
        _tripController!
            .startTrip(_vehicleMileage!, _vehicleVin!, _tempLocation);
        // TODO: update notification
        debugPrint(_tripController?.currentTrip.toString());
      } else {
        _tripController!.updateMileage(_vehicleMileage!);
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _updateDiagnostics: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _endTelemetryCollection() async {
    // TODO: update notification
    debugPrint("Ending telemetry collection...");
    try {
      final endPosition = await _gpsService!.currentPosition;
      _tempLocation = await _gpsService!.getLocationFromPosition(endPosition);
    } catch (e) {
      debugPrint("Error in _endTelemetryCollection: $e");
      _tempLocation = TripLocation(
          street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
    }
    _gpsService = null;
    _tripController!.endTrip(_tempLocation);
    if (_connectedDevice != null) {
      await _disposeConnection(_connectedDevice!);
    }
  }
}
