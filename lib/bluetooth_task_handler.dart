import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:driver_logbook/controllers/trip_controller.dart';
import 'package:driver_logbook/models/trip.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/objectbox.dart';
import 'package:driver_logbook/objectbox.g.dart';
import 'package:driver_logbook/repositories/trip_repository.dart';
import 'package:driver_logbook/services/gps_service.dart';
import 'package:driver_logbook/utils/extra.dart';
import 'package:driver_logbook/utils/vehicle_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:driver_logbook/services/http_service.dart';
import 'package:driver_logbook/utils/help.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// maybe write a separate task handler for ios
// if it is even possible to run a task like that on ios

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
  final int _disconnectRssiThreshold = -65;
  final int _goodRssiThreshold = -55;
  List<String> knownRemoteIds = [];
  Timer? _disconnectTimer;
  DateTime _lastMileageResponseTime = DateTime.now();
  DateTime _lastScanResultTime = DateTime.now();
  int? tripCategoryIndex;
  int? currentRssi;
  bool isDriverNotificatedAboutRegistering = false;
  bool isDriverNotificatedAboutInvalidData = false;
  Trip? tripToSend;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

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
      // keep track of latest mileage response time
      _lastMileageResponseTime = DateTime.now();
      if (_vehicleVin != null && _vehicleMileage != null) {
        // if all vehicle data were received, check if they are correct.
        if (!_isDataValid) {
          _checkData();
        }
      } else {
        // mileage is known by this point, but not vin, so we send the vin request here.
        debugPrint("sending vin request");
        await _sendCommand(vinCommand);
      }
    });
    // use a subscription to update the scan results and save them
    _scanResultsSubscription ??=
        FlutterBluePlus.onScanResults.listen((results) {
      _lastScanResultTime = DateTime
          .now(); // remember resulsts time, to initiate a new scan after 100 sec
      debugPrint("Scan results: $results");
      if (results.isNotEmpty) {
        for (var result in results) {
          if (knownRemoteIds.contains(result.device.remoteId.str)) {
            // skip device that were already scanned
            debugPrint(
                "Remote id already known: ${result.device.remoteId.str}");
            continue;
          } else {
            debugPrint("New remote id added: ${result.device.remoteId.str}");
            knownRemoteIds.add(result.device.remoteId.str);
            // overwrite shared preference with the new list
            _prefs.setStringList("knownRemoteIds", knownRemoteIds);
          }
        }
        // fetch scanned device(s) to initiate new connections
        _fetchDevicesAndConnectToOnlyOne();
      }
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    // wait for data initialize to complete before accessing any data that wasn't initialize
    await _initializationCompleter.future;

    // DEBUGGING: check for trip in database
    for (final trip in TripRepository.getAllTrips()) {
      debugPrint("found trip: ${trip.id}");
    }
    // try to send finished or cancelled
    for (final trip in TripRepository.getFinishedAndCancelledTrips()) {
      debugPrint("found finished trip: ${trip.id}");
      debugPrint(jsonEncode(trip.toJson()));
      final response =
          await HttpService().post(type: ServiceType.trip, body: trip.toJson());
      if (response.statusCode == 201) {
        debugPrint("Successfully transmitted trip");
        _store.box<Trip>().remove(trip.id);
      } else {
        debugPrint(
            "Failed to transmit trip, status code: ${response.statusCode}");
      }
    }

    if (_connectionState == BluetoothConnectionState.connected) {
      await _connectedDevice?.readRssi();
      // read constantly rssi of connected device to trigger rssi stream
    }
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice!.isDisconnecting.first == true) {
      // if no device is connected, check last scan result time and scan again the interval is over
      final difference =
          DateTime.now().difference(_lastScanResultTime).inSeconds;
      if (difference >= 10) {
        debugPrint("No scan results for 100 seconds..Scanning again");
        _scanPeriodicallyForDevices();
      }
      // if no device is connected, nothing more to do here -> return
      return;
    }
    try {
      debugPrint('[BluetoothTaskHandler] Connection state: $_connectionState');
      debugPrint(
          '[BluetoothTaskHandler] Trip: ${_tripController?.currentTrip}');

      // an initialized elm327 and a connected device are the basic requirements for everything what's to follow
      if (_isElm327Initialized &&
          _connectionState == BluetoothConnectionState.connected) {
        // conditions to end a trip: trip in progress and no mileage response for 12 secs

        if (_tripController?.currentTrip != null &&
            _tripController?.currentTrip?.tripStatusEnum ==
                TripStatus.inProgress) {
          final difference =
              DateTime.now().difference(_lastMileageResponseTime).inSeconds;
          if (difference >= 12) {
            debugPrint("No response from ELM327 for 12 seconds..Ending trip");
            await _endTrip();
            return;
          }
        }
        // send mileage request command continuously
        await _sendCommand(_skodaMileageCommand);

        // conditions to start a trip: data has not been checked, and no trip is running
        if (_isDataValid && _tripController?.currentTrip == null) {
          // by this point the mileage controller has initiated a data check,
          // if the check was successfull, then start the trip
          await _startTrip();
        }

        // this is needed when a consecutive trips needs to start
        // for example: when a trip ends all these flags are set to null or false
        // but when a driver doesn't step out of his car, which means the BLE connection still exists
        // and he starts a consecutive trip, then it's necessary to check the elm327 continously
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
    // the trip category and scan from the main app can be received here from the main app.
    debugPrint(
        '[BluetoothTaskHandler] onReceiveData: $data type: ${data.runtimeType}');
    // HttpService().post(type: ServiceType.log, body: {
    //   "status": "onReceiveData",
    //   "data": data.toString(),
    //   "type": data.runtimeType.toString(),
    //   "timestamp": Helper.formatDateString(DateTime.now().toString())
    // });

    if (data is int) {
      // if data is int, it means it is the index of the trip category
      tripCategoryIndex = data;
      if (tripCategoryIndex != null &&
          tripCategoryIndex! >= 0 &&
          tripCategoryIndex! <= 2) {
        debugPrint("New Trip category index: $tripCategoryIndex");
        _prefs.setInt('tripCategory2', tripCategoryIndex!);
      }
    } else if (data is List<dynamic>) {
      // if data is a list, it means it is a list of scanned remote ids from devices
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
    return;
  }

  /// Called when the notification itself is pressed.
  @override
  void onNotificationPressed() {
    return;
  }

  /// Called when the notification itself is dismissed.
  @override
  void onNotificationDismissed() {
    return;
  }

  /// Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // delete/disconnect everything here:
    if (_connectedDevice != null) {
      debugPrint("Disconnecting device on destroy");
      await _connectedDevice?.disconnectAndUpdateStream();
    }
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

    // keep track of the rssi to disconnect a device
    // best case is: a ble connection only establishes when the driver is in his car
    _rssiStreamSubscription ??=
        FlutterBluePlus.events.onReadRssi.listen((event) {
      if (event.device.remoteId == _connectedDevice?.remoteId) {
        currentRssi = event.rssi;

        // If rssi is below -85 for 10+ seconds, disconnect
        if (currentRssi! < _disconnectRssiThreshold) {
          _disconnectTimer ??= Timer(const Duration(seconds: 10), () {
            _disconnectTimer = null;
            _connectedDevice?.disconnectAndUpdateStream();
          });
        }
        // If rssi climbs back above -75, cancel the pending disconnect
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
    final Guid targetService = Guid(dotenv.get('TARGET_SERVICE', fallback: ''));
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

  // create all neccessary data
  Future<void> _initializeData() async {
    debugPrint('[BluetoothTaskHandler] Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    debugPrint('[BluetoothTaskHandler] Initialized SharedPreferences');
    await dotenv.load(fileName: ".env");
    debugPrint('[BluetoothTaskHandler] Initialized dotenv');
    try {
      await ObjectBox.create();
      _store = ObjectBox.store;
    } catch (e) {
      debugPrint('[BluetoothTaskHandler] ObjectBox error: $e');
      HttpService()
          .post(type: ServiceType.log, body: {"status": "ObjectBox error: $e"});
    }
    debugPrint('[BluetoothTaskHandler] Initialized ObjectBox');
    debugPrint('[BluetoothTaskHandler] Initialized SharedPreferences');
    knownRemoteIds = _prefs.getStringList("knownRemoteIds") ?? [];
    debugPrint('[BluetoothTaskHandler] Initialized knownRemoteIds');
    _tripController ??= TripController();
    _gpsService ??= GpsService();
    _initializationCompleter.complete();
    debugPrint('[BluetoothTaskHandler] Initialized data');

    // debugPrint(
    //     "initializiation: ${_objectBox.store.box<Trip>().getAll().toString()}");
    //FlutterForegroundTask.sendDataToMain({'status': 'initialized'});
  }

  // this method is called every minute if and only if the connection state is disconnected
  Future<void> _scanPeriodicallyForDevices() async {
    if (_connectionState == BluetoothConnectionState.connected) {
      return;
    }
    try {
      await FlutterBluePlus.startScan(
          withServices: [Guid(dotenv.get('TARGET_SERVICE', fallback: ''))],
          withNames: [dotenv.get("TARGET_ADV_NAME", fallback: "")],
          timeout: const Duration(seconds: 2));
    } catch (e) {
      debugPrint("Error scanning for devices: $e");
      return;
    }
  }

  Future<void> _fetchDevicesAndConnectToOnlyOne() async {
    _prefs.reload();
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
      // if a device is already connected, prevent connecting to new devices
      if (_connectionState == BluetoothConnectionState.connected) {
        // needed for mid loop handling to avoid race conditions
        debugPrint(
            '[BluetoothTaskHandler] Cant fetch, Already connected to a device: ${_connectedDevice?.remoteId.str}');
        return;
      }
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
    // handle device
    _deviceStateSubscription?.cancel();
    _deviceStateSubscription ??= device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        debugPrint(
            '[BluetoothTaskHandler] Device connected: ${device.remoteId.str}');
        if (_connectedDevice != null) {
          _connectedDevice = device;
          await _requestMtu(device);
          await _discoverCharacteristics(device);
        }
      } else if (state == BluetoothConnectionState.disconnected) {
        if (_tripController?.currentTrip != null) {
          debugPrint("Cancelling trip on bluetooth disconnection");
          _tripController!
              .endTrip(_tempLocation, _vehicleMileage!, TripStatus.cancelled);
        }
        debugPrint(
            '[BluetoothTaskHandler] Device disconnected: ${device.remoteId.str}');
        _connectedDevice = null;
        _writeCharacteristic = null;
        _notifyCharacteristic = null;
        // only connect to the same device after 15 seconds, to prevent connecting immediately again
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
      "ATL0", // Linefeeds Off
      "ATS0", // Spaces Off
      "ATH1", // Headers On
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];
    for (String cmd in initCommands) {
      bool success = await _sendCommand(cmd);
      if (!success) {
        debugPrint("Failed to initialize, probably because of a disconnect");
        return;
      }
      await Future.delayed(const Duration(
          milliseconds: 2500)); // wait for every command to process
    }
    // elm327 is only considered to be complete here.
    _isElm327Initialized = true;
    debugPrint("elm327 initialized");
  }

  // send command to elm327
  Future<bool> _sendCommand(String command) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
      return false;
    }
    debugPrint("Sending command: $command");
    await HttpService().post(
        type: ServiceType.log, body: {"status": "Sending command: $command"});
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await _writeCharacteristic?.write(bytes, withoutResponse: true);
      return true;
    } catch (e) {
      debugPrint("Error in _sendCommand: $e");
      return false;
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

  final List<String> unwantedStrings = [
    "]",
    "[",
    ">",
    "<",
    ":",
    ".",
    " ",
    "\u00A0", // Non-breaking space
    "SEARCHING",
    "STOPPED",
    "ELM327 v1.5",
    "NODATA",
    "TIMEOUT",
    "CANERROR",
    "OK",
  ];

  // process the complete response from elm327
  void _processCompleteResponse(String response) {
    // remove all unnecessary characters or words
    String cleanedResponse = response;
    for (String str in unwantedStrings) {
      cleanedResponse = cleanedResponse.replaceAll(str, "");
    }
    cleanedResponse = cleanedResponse.replaceAll(RegExp(r"\s+"), "").trim();

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
    _tripController!
        .endTrip(_tempLocation, _vehicleMileage!, TripStatus.finished);
    _isElm327Initialized = false;
    _vehicleVin = null;
    _vehicleMileage = null;
    _isDataValid = false;
  }
}
