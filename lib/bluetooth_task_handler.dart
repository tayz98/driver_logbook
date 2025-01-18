import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:elogbook/controllers/trip_controller.dart';
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elogbook/services/http_service.dart';
import 'package:elogbook/utils/help.dart';

// maybe write a separate task handler for ios

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BluetoothTaskHandler());
}

class BluetoothTaskHandler extends TaskHandler {
  // Data
  late Store _store;
  TripController? _tripController;
  late SharedPreferences _prefs;

  // Bluetooth
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<OnReadRssiEvent>? _rssiStreamSubscription;
  final int _disconnectRssiThreshold = -85;
  final int _goodRssiThreshold = -75;
  List<String> knownRemoteIds = [];
  Timer? _disconnectTimer;
  DateTime _lastMileageResponseTime = DateTime.now();
  int? tripCategoryIndex;
  int? currentRssi;
  bool isDriverNotificatedAboutRegistering = false;
  bool isDriverNotificatedAboutInvalidData = false;
  Trip? tripToSend;

  // misc
  GpsService? _gpsService;
  final Completer<void> _initializationCompleter = Completer<void>();

  String? _vehicleVin;
  int? _vehicleMileage;
  Timer? mileageSendCommandTimer;
  Timer? vinSendCommandTimer;
  bool _isDataValid = false;
  TripLocation _tempLocation = TripLocation(
      street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
  String _responseBuffer = '';
  bool _isElm327Initialized = false;
  final String _skodaMileageCommand = "2210E01";
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
    _initializeTime();
    await _initializeBluetooth();

    // listen for mileage response and update the last response time
    _mileageResponseController.stream.listen((_) async {
      _lastMileageResponseTime = DateTime.now();
      if (_vehicleVin != null && _vehicleMileage != null) {
        if (!_isDataValid) {
          debugPrint("executing checkData");
          await HttpService().post(
              type: ServiceType.log, body: {"status": "executing checkData"});
          _checkData();
        }
      } else {
        debugPrint("sending vin request");
        if (_connectionState == BluetoothConnectionState.connected &&
                _connectedDevice != null ||
            await _connectedDevice!.isDisconnecting.first == false) {
          await _sendCommand(vinCommand);
        }
      }
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    tripToSend = _store.box<Trip>().get(3);
    debugPrint(jsonEncode(tripToSend?.toJson()));
    debugPrint("Sending Trip: $tripToSend");
    await HttpService().post(
        type: ServiceType.trip,
        body: tripToSend!
            .toJson()
            .map((key, value) => MapEntry(key, value.toString())));
    //debugPrint(ObjectBox.store.box<Trip>().getAll().toString());

    await HttpService().post(type: ServiceType.log, body: {
      "status": "onRepeatEvent",
      "connectionState": _connectionState.toString(),
      "timestamp": Helper.formatDateString(DateTime.now().toString()),
      "trip_status":
          _tripController?.currentTrip?.tripStatusEnum.toString() ?? "unknown",
    });
    if (_connectionState == BluetoothConnectionState.connected) {
      final int tempRssi = await _connectedDevice?.readRssi() ?? 0;
      if (tempRssi < _disconnectRssiThreshold) {
        await HttpService().post(
            type: ServiceType.log,
            body: {"status": "rssi too low, returning from onRepeatEvent"});
        return;
      }
    }
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice!.isDisconnecting.first == true) {
      await HttpService().post(type: ServiceType.log, body: {
        "status": "device disconnected, returning from onRepeatEvent"
      });
      return;
    }
    await _initializationCompleter.future;
    try {
      // wait for initialization to complete before proceeding
      //debugPrint(ObjectBox.store.box<Driver>().getAll().toString());

      // debug
      debugPrint('[BluetoothTaskHandler] onRepeatEvent: $timestamp');
      debugPrint('[BluetoothTaskHandler] Connection state: $_connectionState');

      debugPrint(
          '[BluetoothTaskHandler] Trip: ${_tripController?.currentTrip}');
      debugPrint('Known remote ids: $knownRemoteIds');

      if (_isElm327Initialized &&
          _connectionState == BluetoothConnectionState.connected) {
        // only start telemetry collection if the elm327 controller is initialized
        if (_tripController?.currentTrip != null &&
            _tripController?.currentTrip?.tripStatusEnum ==
                TripStatus.inProgress) {
          final difference =
              DateTime.now().difference(_lastMileageResponseTime).inSeconds;
          if (difference >= 12) {
            debugPrint("No response from ELM327 for 12 seconds..Ending trip");
            await HttpService().post(
                type: ServiceType.log,
                body: {"status": "No response from ELM327 for 12 seconds"});
            await _endTrip();
            return;
          }
        }
        _tripController ??= TripController(ObjectBox.store, _prefs);
        _gpsService ??= GpsService();
        await _sendCommand(_skodaMileageCommand); // query mileage continuously
        if (_isDataValid && _tripController?.currentTrip == null) {
          await HttpService().post(
              type: ServiceType.log,
              body: {"status": "Data is valid, starting trip"});
          await _startTrip();
        }
        // if the elm327 has not responded and therefore the initialization has been set to false
        // but the device is still connected and the driver  plans to start a consecutive trip
        // the initialization has to be done again, maybe add another boolean like hasTripEnded for more robustness
      } else if (!_isElm327Initialized &&
          _connectionState == BluetoothConnectionState.connected &&
          _writeCharacteristic != null &&
          _notifyCharacteristic != null) {
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
    HttpService().post(type: ServiceType.log, body: {
      "status": "onReceiveData",
      "data": data.toString(),
      "type": data.runtimeType.toString(),
      "timestamp": Helper.formatDateString(DateTime.now().toString())
    });

    // only the trip category index is received as int from the main app
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
      await _fetchDevicesAndConnectToOnlyOne();
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
    await HttpService().post(type: ServiceType.log, body: {
      "status": "onDestroy",
      "timestamp": Helper.formatDateString(timestamp.toString())
    });
    if (_connectedDevice != null) {
      debugPrint("Disconnecting device on destroy");
      await _connectedDevice?.disconnectAndUpdateStream();
    }
    // if any trip was in progress, cancel it
    if (Platform.isAndroid && _tripController?.currentTrip != null) {
      debugPrint("Cancelling trip on destroy");
      _tripController!.cancelTrip(_tempLocation, _vehicleMileage);
    }
    // on ios: maybe pause and resume, because tasks could be destroyed more often
    _store.close();
    _tripController = null;
    _mileageResponseController.close();
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
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
    debugPrint('[BluetoothTaskHandler] Initializing Bluetooth...');
    FlutterBluePlus.setOptions(restoreState: true);
    //FlutterBluePlus.setLogLevel(LogLevel.verbose);
    _fetchDevicesAndConnectToOnlyOne();

    _rssiStreamSubscription ??=
        FlutterBluePlus.events.onReadRssi.listen((event) {
      if (event.device.remoteId == _connectedDevice?.remoteId) {
        currentRssi = event.rssi;

        // If we are below -85 for 5+ seconds, we disconnect
        if (currentRssi! < _disconnectRssiThreshold) {
          _disconnectTimer ??= Timer(const Duration(seconds: 5), () {
            _disconnectTimer = null;
            _connectedDevice?.disconnectAndUpdateStream();
          });
        }
        // If we climb back above -75, we cancel the pending disconnect
        else if (currentRssi! > _goodRssiThreshold) {
          if (_disconnectTimer != null) {
            _disconnectTimer?.cancel();
            _disconnectTimer = null;
          }
        }
      }
    });
  }

  void _initializeTime() async {
    await initializeDateFormatting('de_DE');
    Intl.defaultLocale = 'de_DE';
  }

  Future<void> _discoverCharacteristics(BluetoothDevice device) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
      return;
    }
    final Guid targetService = Guid("0000fff0-0000-1000-8000-00805f9b34fb");
    List<BluetoothService> services =
        await _connectedDevice!.discoverServices();
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
    if (_connectionState == BluetoothConnectionState.disconnected) return;
    try {
      await dev.requestMtu(128, predelay: 0);
      debugPrint(
          "[BluetoothTaskHandler] Device MTU after request: ${_connectedDevice?.mtu}");
    } catch (e) {
      return;
    }
  }

  Future<void> _initializeData() async {
    debugPrint('[BluetoothTaskHandler] Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    try {
      await ObjectBox.create();
      _store = ObjectBox.store;
    } catch (e) {
      debugPrint('[BluetoothTaskHandler] ObjectBox error: $e');
      HttpService()
          .post(type: ServiceType.log, body: {"status": "ObjectBox error: $e"});
    }
    debugPrint('[BluetoothTaskHandler] Initialized ObjectBox');
    _tripController = TripController(ObjectBox.store, _prefs);
    debugPrint('[BluetoothTaskHandler] Initialized SharedPreferences');
    knownRemoteIds = _prefs.getStringList("knownRemoteIds") ?? [];
    debugPrint('[BluetoothTaskHandler] Initialized knownRemoteIds');
    _initializationCompleter.complete();
    debugPrint('[BluetoothTaskHandler] Initialized data');
    await HttpService()
        .post(type: ServiceType.log, body: {"status": "initialized Data"});
    // debugPrint(
    //     "initializiation: ${_objectBox.store.box<Trip>().getAll().toString()}");
    //FlutterForegroundTask.sendDataToMain({'status': 'initialized'});
  }

  Future<void> _fetchDevicesAndConnectToOnlyOne() async {
    debugPrint('[BluetoothTaskHandler] Fetching devices and connecting...');
    debugPrint("knownRemoteIds: $knownRemoteIds");
    if (knownRemoteIds.isEmpty) {
      debugPrint('[BluetoothTaskHandler] No known devices to connect to.');
      return;
    }

    if (_connectedDevice != null) {
      debugPrint(
          '[BluetoothTaskHandler] Cant fetch, Already connected to a device: ${_connectedDevice?.remoteId.str}');
      return;
    }
    for (var id in knownRemoteIds) {
      if (_connectionState == BluetoothConnectionState.connected) {
        // needed for mid loop handling
        debugPrint(
            '[BluetoothTaskHandler] Cant fetch, Already connected to a device: ${_connectedDevice?.remoteId.str}');
        return;
      }
      // skip already fetched devices
      // if (_knownDevices.any((device) => device.remoteId.str == id)) {
      //   continue;
      // }

      try {
        final device = BluetoothDevice.fromId(id);
        await device.connectAndUpdateStream();
        _connectedDevice = device;
        _listenToDeviceState(device);
        break;
      } catch (e) {
        debugPrint('[BluetoothTaskHandler] Connect error: $e');
        return;
      }
    }
  }

  void _listenToDeviceState(BluetoothDevice device) {
    _deviceStateSubscription?.cancel();
    _deviceStateSubscription ??= device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        debugPrint(
            '[BluetoothTaskHandler] Device connected: ${device.remoteId.str}');
        HttpService().post(type: ServiceType.log, body: {
          "status": "Device connected",
          "remoteId": device.remoteId.str
        });
        if (_connectedDevice != null) {
          _connectedDevice = device;
          await _requestMtu(device);
          await _discoverCharacteristics(device);
        }
      } else if (state == BluetoothConnectionState.disconnected) {
        debugPrint(
            '[BluetoothTaskHandler] Device disconnected: ${device.remoteId.str}');
        _connectedDevice = null;
        _writeCharacteristic = null;
        _notifyCharacteristic = null;
        Future.delayed(const Duration(seconds: 15), () async {
          await _fetchDevicesAndConnectToOnlyOne();
        });
      }
    });
  }
  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Elm327
  // --------------------------------------------------------------------------

  Future<void> _initializeElm327() async {
    if (_isElm327Initialized) return;
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
      return;
    }
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
    _isElm327Initialized = true;
    await HttpService()
        .post(type: ServiceType.log, body: {"status": "ELM327 initialized"});
  }

  // send command to elm327
  Future<void> _sendCommand(String command) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
      return;
    }
    debugPrint("Sending command: $command");
    await HttpService().post(
        type: ServiceType.log, body: {"status": "Sending command: $command"});
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await _writeCharacteristic?.write(bytes, withoutResponse: true);
    } catch (e) {
      debugPrint("Error in _sendCommand: $e");
    }
  }

  // check if VIN and mileage are valid
  void _checkData() {
    debugPrint("Checking data...");
    bool vin = _checkVin();
    bool mileage = _checkMileage();
    if (vin && mileage) {
      _isDataValid = true;
    } else {
      _isDataValid = false;
      if (!isDriverNotificatedAboutInvalidData) {
        updateNotificationText("Daten fehlerhaft",
            "Bitte setzen Sie sich mit dem Support in Verbindung.");
        isDriverNotificatedAboutInvalidData = true;
      }
    }
  }

  // check if VIN is valid
  bool _checkVin() {
    if (_vehicleVin?.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      if (vinRegex.hasMatch(_vehicleVin!)) {
        return true;
      }
    }
    return false;
  }

  // check if mileage is valid
  bool _checkMileage() {
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

  Future<void> _startTrip() async {
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
        HttpService().post(type: ServiceType.log, body: {
          "status": "Trip started",
          "vehicleMileage": _vehicleMileage.toString(),
          "vehicleVin": _vehicleVin.toString(),
          "tempLocation": _tempLocation.toString()
        });
        updateNotificationText("Fahrtaufzeichnung", "Die Fahrt hat begonnen");
        debugPrint(_tripController?.currentTrip.toString());
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _updateDiagnostics: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _endTrip() async {
    updateNotificationText("Fahrt beendet", "Die Fahrt wurde beendet");
    HttpService().post(type: ServiceType.log, body: {"status": "Ending trip"});
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
    _tripController!.endTrip(_tempLocation, _vehicleMileage!);
    _isElm327Initialized = false;
    _vehicleVin = null;
    _vehicleMileage = null;
    _isDataValid = false;
  }
}
