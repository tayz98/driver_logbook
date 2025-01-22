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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:driver_logbook/models/vehicle.dart';

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
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription;
  StreamSubscription<OnReadRssiEvent>? _rssiStreamSubscription;
  final int _disconnectRssiThreshold = -65;
  final int _goodRssiThreshold = -55;
  static const int _rssiDuration = 10;
  List<String> knownRemoteIds = [];
  Timer? _rssiDisconnectTimer;
  int? tripCategoryIndex;
  StreamSubscription<List<int>>? _dataSubscription;

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
  Timer? _mileageSendCommandTimer;
  Timer? _mileageInactivityTimer;

  Timer? _vinSendCommandTimer;
  Timer? _dataTimeoutTimer;

  TripLocation _tempLocation = TripLocation(
      street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
  String _responseBuffer = '';
  bool _isElm327Initialized = false;
  static const String vinCommand = "0902";
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
    await VehicleUtils.initializeVehicleModels();

    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      if (_connectionState == event.connectionState) return;
      // don't connect to new devices if already connected
      _connectionState = event.connectionState;
      if (event.connectionState == BluetoothConnectionState.connected) {
        _connectedDevice = event.device;
        await _requestMtu(event.device);
        await _discoverCharacteristics(event.device);
      } else {
        if (_tripController?.currentTrip != null) {
          debugPrint("Cancelling trip on bluetooth disconnect");
          _tripController!
              .endTrip(_tempLocation, _vehicleMileage!, TripStatus.cancelled);
        }
        _connectedDevice = null;
        _writeCharacteristic = null;
        _notifyCharacteristic = null;
        _isElm327Initialized = false;
        Future.delayed(const Duration(seconds: 10), () async {
          await _fetchAndConnectToDevices();
        });
      }
      debugPrint("Connection state: $_connectionState");
    });
    // use a subscription to update the scan results and save them
    _scanResultsSubscription ??=
        FlutterBluePlus.onScanResults.listen((results) {
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
        _fetchAndConnectToDevices();
      }
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
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
        TripRepository.deleteTrip(trip.id);
      } else {
        debugPrint(
            "Failed to transmit trip, status code: ${response.statusCode}");
      }
    }

    debugPrint('[BluetoothTaskHandler] Connection state: $_connectionState');
    debugPrint('[BluetoothTaskHandler] Trip: ${_tripController?.currentTrip}');
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
      await _fetchAndConnectToDevices();
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

    _disposeAllTimerAndStreams();
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
    // scan for devices every 100 seconds if the connection state is disconnected
    // for testing it's 10 seconds
    _rssiDisconnectTimer ??=
        Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_connectionState == BluetoothConnectionState.disconnected) {
        _scanDevices();
      }
    });

    debugPrint('[BluetoothTaskHandler] Initializing Bluetooth...');
    FlutterBluePlus.setOptions(restoreState: true);
    //FlutterBluePlus.setLogLevel(LogLevel.verbose);
    _fetchAndConnectToDevices();

    // keep track of the rssi to disconnect a device
    // best case is: a ble connection only establishes when the driver is in his car
    _rssiStreamSubscription ??=
        FlutterBluePlus.events.onReadRssi.listen((event) {
      if (event.device.remoteId == _connectedDevice?.remoteId) {
        currentRssi = event.rssi;

        // If rssi is below -85 for 10+ seconds, disconnect
        if (currentRssi! < _disconnectRssiThreshold) {
          _rssiDisconnectTimer ??=
              Timer(const Duration(seconds: _rssiDuration), () {
            _rssiDisconnectTimer = null;
            _connectedDevice?.disconnectAndUpdateStream();
          });
        }
        // If rssi climbs back above -75, cancel the pending disconnect
        else if (currentRssi! > _goodRssiThreshold) {
          if (_rssiDisconnectTimer != null) {
            _rssiDisconnectTimer?.cancel();
            _rssiDisconnectTimer = null;
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
      _dataSubscription ??= _notifyCharacteristic!.lastValueStream.listen(
        (data) {
          _dataTimeoutTimer?.cancel();
          _dataTimeoutTimer = Timer(const Duration(seconds: 10), () {
            debugPrint("Keine Daten seit 10 Sekunden");
            if (_tripController?.currentTrip != null) {
              _endTrip();
            }
          });

          handleReceivedData(data);
        },
        onError: (e) {
          debugPrint("Stream-Fehler: $e");
        },
        cancelOnError: false,
      );
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
  }

  // this method is called every minute if and only if the connection state is disconnected
  Future<void> _scanDevices() async {
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

  Future<void> _fetchAndConnectToDevices() async {
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
        break;
      } catch (e) {
        debugPrint('[BluetoothTaskHandler] Connect error: $e');
        return;
      }
    }
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
      if (cmd == "ATZ") {
        await Future.delayed(const Duration(
            milliseconds: 2500)); // wait for every command to process
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    // elm327 is only considered to be complete here.
    _isElm327Initialized = true;
    debugPrint("ELM327 initialized");

    _vinSendCommandTimer ??=
        Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        if (_isElm327Initialized && _vehicleVin == null) {
          debugPrint("Sending VIN request");
          await _sendCommand(vinCommand);
        } else {
          _vinSendCommandTimer?.cancel();
          _vinSendCommandTimer = null;
          _startMileageTimer();
        }
      } catch (e) {
        debugPrint("Error in _vinSendCommandTimer: $e");
      }
    });
  }

  void _startTripIfNeeded() {
    if (_tripController?.currentTrip == null &&
        _vehicleVin != null &&
        _vehicleMileage != null) {
      _startTrip();
    }
  }

  void _startMileageTimer() {
    debugPrint("Starting mileage timer");
    _mileageSendCommandTimer ??=
        Timer.periodic(const Duration(seconds: 4), (_) async {
      _connectedDevice?.readRssi();
      try {
        if (_isElm327Initialized && _vehicleVin != null) {
          debugPrint("Sending mileage request");
          await _sendCommand(
              VehicleUtils.getVehicleMileageCommand(_vehicleVin!));
        }
      } catch (e) {
        debugPrint("Error in _startMileageTimer: $e");
      }
    });
  }

  // send command to elm327
  Future<bool> _sendCommand(String command) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
      return false;
    }
    debugPrint("Sending command: $command");
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

  // check if VIN is valid
  bool _checkVin(String vin) {
    if (vin.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      if (vinRegex.hasMatch(vin)) {
        return true;
      }
    }
    return false;
  }

  // check if mileage is valid
  bool _checkMileage(int mileage) {
    if (mileage >= 0 && mileage <= 2000000) {
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
    "?",
    ":",
    ".",
    " ",
    "\u00A0", // Non-breaking space
    "SEARCHING",
    "STOPPED",
    "ELM327v15",
    "NODATA",
    "TIMEOUT",
    "CANERROR",
    "BUSERROR",
    "DATAERROR",
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
      _handleResponseToMileageCommand(cleanedResponse);
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
    final vin = VehicleUtils.getVehicleVin(response);
    final isVinValid = _checkVin(vin);
    if (isVinValid) {
      _vehicleVin = vin;
      debugPrint("VIN: $_vehicleVin");
    } else {
      debugPrint("VIN is invalid");
    }
  }

  void _handleResponseToMileageCommand(String response) {
    if (_vehicleVin == null) {
      debugPrint("Vehicle VIN is null, can't process mileage response");
      return;
    }
    final mileage = VehicleUtils.getVehicleKm(_vehicleVin!, response);
    final isMileageValid = _checkMileage(mileage);
    if (isMileageValid) {
      _vehicleMileage = mileage;
      debugPrint("Mileage: $_vehicleMileage");
      _startTripIfNeeded();
    } else {
      debugPrint("Mileage is invalid");
    }
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
        _tripController!.startTrip(
            _vehicleMileage!, Vehicle.fromVin(_vehicleVin!), _tempLocation);
        updateNotificationText("Fahrtaufzeichnung", "Die Fahrt hat begonnen");

        debugPrint(_tripController?.currentTrip.toString());
      }
    } catch (e, stackTrace) {
      debugPrint('Error in _updateDiagnostics: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _endTrip() async {
    _mileageInactivityTimer?.cancel();
    updateNotificationText("Fahrt beendet", "Die Fahrt wurde beendet");
    debugPrint("Die Fahrt wurde beendet");
    try {
      final endPosition = await _gpsService!.currentPosition;
      _tempLocation = await _gpsService!.getLocationFromPosition(endPosition);
    } catch (e) {
      debugPrint("Error in _endTelemetryCollection: $e");
      _tempLocation = TripLocation(
          street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
    }
    _tripController!
        .endTrip(_tempLocation, _vehicleMileage!, TripStatus.finished);
    _vehicleVin = null;
    _vehicleMileage = null;
    _mileageSendCommandTimer?.cancel();
    _mileageSendCommandTimer = null;
    _vinSendCommandTimer?.cancel();
    _vinSendCommandTimer = null;
    _isElm327Initialized = false;
    if (_connectionState == BluetoothConnectionState.connected) {
      await _connectedDevice?.disconnectAndUpdateStream();
    }
  }

  void _disposeAllTimerAndStreams() {
    _mileageResponseController.close();
    _mileageSendCommandTimer?.cancel();
    _vinSendCommandTimer?.cancel();
    _rssiDisconnectTimer?.cancel();
    _connectionStateSubscription?.cancel();
    _rssiStreamSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _mileageResponseController.close();
    _mileageInactivityTimer?.cancel();
  }
}
