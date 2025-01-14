import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:elogbook/controllers/trip_controller.dart';
import 'package:elogbook/models/driver.dart';
import 'package:elogbook/models/trip.dart';
import 'package:elogbook/models/trip_status.dart';
import 'package:elogbook/objectbox.dart';
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
  late ObjectBox _objectBox;
  late TripController _tripController;
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

  // misc
  GpsService? _gpsService;
  final Completer<void> _initializationCompleter = Completer<void>();

  String? _vehicleVin;
  int? _vehicleMileage;
  Timer? mileageSendCommandTimer;
  String _responseBuffer = '';
  bool isElm327Initialized = false;
  final String skodaMileageCommand = "2210E01";
  final String vinCommand = "0902";
  final StreamController<void> _mileageResponseController =
      StreamController<void>.broadcast();
  final ForegroundTaskOptions defaultTaskOptions = ForegroundTaskOptions(
    eventAction: ForegroundTaskEventAction.repeat(4000),
    autoRunOnBoot: true,
    autoRunOnMyPackageReplaced: true,
    allowWakeLock: true,
    allowWifiLock: true,
  );

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BluetoothTaskHandler] onStart: ${starter.name}');
    await _initializeData();
    await _initializeBluetooth();

    _mileageResponseController.stream.listen((_) {
      _lastMileageResponseTime = DateTime.now();
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    debugPrint(_objectBox.store.box<Trip>().getAll().toString());
    debugPrint(_objectBox.store.box<Driver>().getAll().toString());

    debugPrint('[BluetoothTaskHandler] onRepeatEvent: $timestamp');
    debugPrint('[BluetoothTaskHandler] Connection state: $_connectionState');
    //debugPrint('[BluetoothTaskHandler] Trip: ${_tripController.currentTrip}');

    debugPrint('Known remote ids: $knownRemoteIds');
    if (isElm327Initialized) {
      if (_tripController.currentTrip != null &&
          _tripController.currentTrip!.tripStatusEnum ==
              TripStatus.inProgress) {
        final difference =
            DateTime.now().difference(_lastMileageResponseTime).inSeconds;
        if (difference > 15) {
          _endTelemetryCollection();
          return;
        }
      }
      _gpsService ??= GpsService();
      await _sendCommand(skodaMileageCommand);
      await Future.delayed(const Duration(seconds: 1));
      if (await _checkData() && _tripController.currentTrip != null) {
        await _updateDiagnostics();
      } else {
        debugPrint("Data not valid or no trip started yet..Repeating");
      }
    }

    // Send data to main isolate if needed
    // final Map<String, dynamic> data = {
    //   "event": "onRepeatEvent",
    //   "timestampMillis": timestamp.millisecondsSinceEpoch,
    // };
    // FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  void onReceiveData(Object data) async {
    if (data is Map && data['command'] == 'get_store_reference') {
      debugPrint(
          '[BluetoothTaskHandler] Received command: get_store_reference');

      final ByteData storeRef = _objectBox.store.reference;
      final List<int> serializedStoreRef = storeRef.buffer.asUint8List();
      FlutterForegroundTask.sendDataToMain({'storeRef': serializedStoreRef});
    }
    debugPrint(
        '[BluetoothTaskHandler] onReceiveData: $data type: ${data.runtimeType}');

    await _initializationCompleter.future;
    if (data is int) {
      tripCategoryIndex = data;
      if (tripCategoryIndex != null &&
          tripCategoryIndex! >= 0 &&
          tripCategoryIndex! <= 2) {
        debugPrint("New Trip category index: $tripCategoryIndex");
        _prefs.setInt('tripCategory2', tripCategoryIndex!);
      }
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
    _objectBox.close();
    debugPrint('[BluetoothTaskHandler] onDestroy');
    // Cleanup resources
  }

  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Bluetooth
  // --------------------------------------------------------------------------

  Future<void> _initializeBluetooth() async {
    debugPrint('[BluetoothTaskHandler] Initializing Bluetooth...');
    FlutterBluePlus.setOptions(restoreState: true);
    FlutterBluePlus.setLogLevel(LogLevel.verbose);
    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen(
      (event) async {
        _connectionState = event.connectionState;
        if (_connectionState == BluetoothConnectionState.connected) {
          _connectedDevice = event.device;
        }
        final int currentRssi = await _connectedDevice!.readRssi();
        debugPrint(
            '[BluetoothTaskHandler] Device ${_connectedDevice!.remoteId.str} RSSI: $currentRssi');
        if (currentRssi < _disconnectRssiThreshold) {
          debugPrint(
              '[BluetoothTaskHandler] Disconnecting device due to low RSSI: $currentRssi');
          await _disposeConnection(_connectedDevice!);
        }
        await _requestMtu(_connectedDevice!);
        await _discoverCharacteristics(_connectedDevice!);
        _trackRssi(
            dev: _connectedDevice!, interval: const Duration(seconds: 5));
        if (_connectionState == BluetoothConnectionState.disconnected) {
          if (_connectedDevice != null) {
            await _disposeConnection(_connectedDevice!);
          }
          // needed because when disconnect() is used on autoConnect
          // the device is not auto connecting anymore
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
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    await _rssiStreamSubscription?.cancel();
    _rssiStreamSubscription = null;
    await _connectedDevice?.disconnectAndUpdateStream();
  }

  Future<void> _initializeData() async {
    debugPrint('[BluetoothTaskHandler] Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    try {
      _objectBox = await ObjectBox.create();
    } catch (e) {
      debugPrint('[BluetoothTaskHandler] ObjectBox error: $e');
    }
    debugPrint('[BluetoothTaskHandler] Initialized ObjectBox');
    _tripController = TripController(_objectBox.store, _prefs);
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
            await Future.delayed(const Duration(seconds: 1));
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
    await _writeCharacteristic?.write(bytes, withoutResponse: true);
  }

  // check if VIN and mileage are valid
  Future<bool> _checkData() async {
    debugPrint("Checking data...");
    bool vin = await _checkVin();
    bool mileage =
        _checkMileageOfSkoda(); // mileage already known by now, that's why it's not awaited
    return vin && mileage;
  }

  // check if VIN is valid
  Future<bool> _checkVin() async {
    if (_vehicleVin == null) {
      for (int i = 0; i < 3; i++) {
        await _sendCommand(vinCommand);
        // if VIN takes too long to receive, send the command again
        await Future.delayed(const Duration(milliseconds: 2000));
        if (_vehicleVin != null) {
          break;
        }
      }
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

  Future<void> _updateDiagnostics() async {
    if (_tripController.currentTrip == null) {
      final position = await _gpsService!.currentPosition();
      final location = await _gpsService!.getLocationFromPosition(position);
      _tripController.startTrip(_vehicleMileage!, _vehicleVin!, location);
    } else {
      _tripController.updateMileage(_vehicleMileage!);
    }
  }

  Future<void> _endTelemetryCollection() async {
    debugPrint("Ending telemetry collection...");
    final endPosition = await _gpsService!.currentPosition();
    final endLocation = await _gpsService!.getLocationFromPosition(endPosition);
    _gpsService = null;
    _tripController.endTrip(endLocation);
    if (_connectedDevice != null) {
      await _disposeConnection(_connectedDevice!);
    }
  }

  void _sendStoreReferenceToMain() {
    final ByteData storeRef = _objectBox.store.reference;
    // Send the store reference to the main isolate
    FlutterForegroundTask.sendDataToMain(storeRef);
    debugPrint('[BluetoothTaskHandler] Sent store reference to main isolate');
  }
}
