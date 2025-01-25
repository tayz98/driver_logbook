import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:driver_logbook/controllers/trip_controller.dart';
import 'package:driver_logbook/models/trip_location.dart';
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
import 'package:driver_logbook/utils/custom_log.dart';

// maybe write a separate task handler for ios
// if it is even possible to run a task like that on ios

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BluetoothTaskHandler());
}

class BluetoothTaskHandler extends TaskHandler {
  // Objects:
  late Store _store; // objectbox store for storing trips
  TripController? _tripController; // trip controller for managing trips
  late SharedPreferences
      _prefs; // shared preferences for storing known remote ids and category index
  GpsService? _gpsService; // used for getting the location

  // Bluetooth related:
  BluetoothDevice? _activeDevice; // connected device
  BluetoothCharacteristic? _writeCharacteristic; // data to send to elm327
  BluetoothCharacteristic? _notifyCharacteristic; // data to receive from elm327
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected; // default connection state
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription; // for handling connection states
  List<String> knownRemoteIds = []; // list of known remote ids to connect to
  int? _tripCategoryIndex; // index of the trip category
  // StreamSubscription<List<int>>?
  //     _dataSubscription; // for obversing incoming data from elm327
  StreamSubscription<List<ScanResult>>?
      _scanResultsSubscription; //  for handling scan results
  late Guid targetService;
  late String targetName;

  // telemetry-related:
  String? _vehicleVin; // used for saving the vin
  int? _vehicleMileage; // used for saving and tracking the mileage
  double?
      _voltageVal; // used for checking voltage of the vehicle (engine runnning)
  bool _isElm327Initialized = false; // default state of elm327
  TripLocation? _tempLocation;
  Vehicle? _tempVehicle;
  static const String vinCommand =
      "0902"; // standardized obd2 command for requesting the vin
  static const String voltageCommand =
      "ATRV"; // ELM327 system command for checking vehicle voltage

  // Timer:
  Timer?
      _mileageSendCommandTimer; // used for sending mileage requests continuously
  Timer? _dataTimeoutTimer; // used for ending the trip if no data is received
  Timer?
      _elm327Timer; // used for reinitializing elm327 if a consecutive trip happens
  Timer? _readRssiTimer; // used for reading the rssi continuously
  Timer? _tripTimeoutTimer; // used for ending the trip if no data is received
  Timer? _tripCancelTimer; // used for cancelling the trip if connection is lost
  Timer? _bleDisconnectTimer; // timer to scan for devices if disconnected
  Timer? _voltageTimer; // timer to read the voltage of the vehicle
  // voltage is used to determine if the engine is running, which is used to determine if a trip is running

  String _responseBuffer = ''; // buffer for incoming data from the elm327

  // --------------------------------------------------------------------------
  // PUBLIC METHODS: TaskHandler
  // --------------------------------------------------------------------------

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    CustomLogger.d('[BluetoothTaskHandler] onStart');
    await _initializeData(); // e.g. shared preferences, objectbox, etc.
    _initializeTime(); // initialize time for date formatting
    await _initializeBluetooth(); // complete bluetooth initialization
    CustomLogger.i('onStart completed');
  }

  /// only used for trasmitting trips to the remote server
  @override
  void onRepeatEvent(DateTime timestamp) async {
    CustomLogger.d('[BluetoothTaskHandler] onRepeatEvent'); // debug
    final tripsToTransmit = TripRepository.getFinishedAndCancelledTrips();
    // if (tripsToTransmit.isEmpty) {
    //   CustomLogger.d("No trips to transmit");
    //   return;
    // }
    for (final trip in tripsToTransmit) {
      final response =
          await HttpService().post(type: ServiceType.trip, body: trip.toJson());
      if (response.statusCode == 201) {
        CustomLogger.i("Trip transmitted successfully");
        TripRepository.deleteTrip(trip.id);
      } else {
        CustomLogger.w("Error in transmitting trip: ${response.body}");
      }
    }
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
    await _cleanUpAndResetData();
    CustomLogger.d("Data cleaned up");
    CustomLogger.d("[BluetoothTaskHandler] onDestroy");
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
  Future<void> _cleanUpAndResetData() async {
    _cancelAllStreams();
    _cancelALlTimersExceptBleDisconnect();
    if (_tripController?.currentTrip != null) {
      await _endTrip();
    }
    _cancelALlTimersExceptBleDisconnect();
    _bleDisconnectTimer?.cancel();
    _bleDisconnectTimer = null;
    _resetAllTripVariables();
    _resetAllMiscVariables();
  }

  // cancels all timer except ble disconnect timer
  void _cancelALlTimersExceptBleDisconnect() {
    _mileageSendCommandTimer?.cancel();
    _mileageSendCommandTimer = null;
    _dataTimeoutTimer?.cancel();
    _dataTimeoutTimer = null;
    _elm327Timer?.cancel();
    _elm327Timer = null;
    _readRssiTimer?.cancel();
    _readRssiTimer = null;
    _tripTimeoutTimer?.cancel();
    _tripTimeoutTimer = null;
    _tripCancelTimer?.cancel();
    _tripCancelTimer = null;
    _voltageTimer?.cancel();
    _voltageTimer = null;
  }

  // reset all trip related variables
  void _resetAllTripVariables() {
    _vehicleMileage = null;
    _vehicleVin = null;
    _isElm327Initialized = false;
    _notifyCharacteristic = null;
    _writeCharacteristic = null;
    _activeDevice = null;
    _responseBuffer = '';
    _activeDevice = null;
    _voltageVal = null;
    _tempLocation = null;
    _tempVehicle = null;
  }

  // reset all data related variables
  void _resetAllMiscVariables() {
    _tripController = null;
    _gpsService = null;
    _store.close();
  }

  // cancel all streams
  void _cancelAllStreams() {
    _connectionStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _connectionStateSubscription = null;
    _scanResultsSubscription = null;
  }

  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Bluetooth
  // --------------------------------------------------------------------------

  Future<void> _initializeBluetooth() async {
    FlutterBluePlus.setOptions(restoreState: true);
    CustomLogger.d('[BluetoothTaskHandler] Initializing Bluetooth...');
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
    // start scanning for devices continuously when no device is connected
    _bleDisconnectTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // in production set to to 100 seconds
      CustomLogger.d("BLE disconnect timer started");
      if (_connectionState == BluetoothConnectionState.disconnected) {
        CustomLogger.d("Starting scan after 10 seconds and no connection");
        _scanDevices();
      }
    });
    CustomLogger.d(
        "Fetching and connecting to devices in _initializeBluetooth");
    await _fetchAndConnectToDevices();
    CustomLogger.d("_initializeBluetooth completed");

    /// listen  for connection state changes and manage the connection
    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      _connectionState = event.connectionState;
      CustomLogger.i("Connection state: $_connectionState");
      if (_connectionState == BluetoothConnectionState.connected) {
        _bleDisconnectTimer?.cancel();
        _bleDisconnectTimer = null;
        // initialize device on connection
        await setupConnectedDevice(event.device);
        // if connected, cancel scans
        CustomLogger.d("BLE disconnect timer cancelled on connection");
      } else if (_connectionState == BluetoothConnectionState.disconnected) {
        // thinking.. if a device disconnected, check if previously connected devices can be reconnected
        if (!event.device.isAutoConnectEnabled) {
          // if auto connect is disabled by disconnecting, enable it again
          // this usually shouldn't happen, but for safety reasons we check it
          event.device
              .connectAndUpdateStream(); // without wait, to not block subsequent code
        }
        if (FlutterBluePlus.connectedDevices.length == 1) {
          // thought process:
          // with BLE the app can connect to multiple devices, but only one connection is "active/used"
          // for a trip, we only need one device to be connected
          // so if we start driving and other devices but one disconnect, we know for sure that the current connected device is the one we need
          // we could also track the rssi, but it would overcomplicate things
          setupConnectedDevice(FlutterBluePlus.connectedDevices.first);
        }
        _tripCancelTimer?.cancel();
        CustomLogger.d("Trip cancel timer cancelled");
        if (_tripController?.currentTrip != null) {
          Future.delayed(const Duration(seconds: 15), () {
            CustomLogger.d(
                "Waiting 15 seconds to check if device is still disconnected");
            if (_connectionState == BluetoothConnectionState.disconnected) {
              CustomLogger.i("Device is still disconnected, cancelling trip");
              _endTrip();
            } else {
              CustomLogger.i("Device is connected again, cancelling timer");
              return;
              // if a trip is in progress, but the bluetooth connection got interrupted for a short time, return.
            }
          });
        }
        _cancelALlTimersExceptBleDisconnect();
        _resetAllTripVariables();
        CustomLogger.i("Setting all variables to null on disconnection");
        // start scanning for devices continuously again
        _bleDisconnectTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          // usually 100 seconds in production
          CustomLogger.d(
              "BLE disconnect timer started again after disconnection");
          if (_connectionState == BluetoothConnectionState.disconnected) {
            CustomLogger.d("Starting scan after 10 seconds and no connection");
            _scanDevices();
          }
        });
      }
    });
    // use a subscription to update the scan results and save them
    _scanResultsSubscription ??=
        FlutterBluePlus.onScanResults.listen((results) async {
      CustomLogger.d("Scan results: $results");
      if (results.isNotEmpty) {
        for (var result in results) {
          if (knownRemoteIds.contains(result.device.remoteId.str)) {
            // skip device that were already scanned
            CustomLogger.d(
                "Remote id already known: ${result.device.remoteId.str}");
            continue;
          } else {
            CustomLogger.d(
                "New remote id scanned and added: ${result.device.remoteId.str}");
            knownRemoteIds.add(result.device.remoteId.str);
            // overwrite shared preference with the new list
            _prefs.setStringList("knownRemoteIds", knownRemoteIds);
          }
        }
        // fetch scanned device(s) to initiate new connections
        await _fetchAndConnectToDevices();
      }
    });
  }

  // not needed for now
  void _initializeTime() async {
    await initializeDateFormatting('de_DE');
    Intl.defaultLocale = 'de_DE';
  }

  Future<void> _discoverCharacteristicsAndStartElm327(
      BluetoothDevice device) async {
    if (FlutterBluePlus.connectedDevices.isEmpty) {
      CustomLogger.d("Can't discover characteristics, no connected device");
      return;
    }
    CustomLogger.d("Discovering characteristics for service: $targetService");
    List<BluetoothService> services = await _activeDevice!.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            _writeCharacteristic = c;
            CustomLogger.d("Write characteristic found: ${c.uuid}");
          }
          if (c.properties.notify) {
            _notifyCharacteristic = c;
            CustomLogger.d("Notify characteristic found: ${c.uuid}");
          }
        }
      }
    }

    if (_writeCharacteristic != null && _notifyCharacteristic != null) {
      CustomLogger.d(
          "Characteristics found, setting notify value to true and start listening");
      await _notifyCharacteristic!.setNotifyValue(true);
      final dataSubscription =
          _notifyCharacteristic!.lastValueStream.listen((data) {
        handleReceivedData(data);
      });
      // TODO: check if this makes any problems, maybe it's not needed
      _activeDevice?.cancelWhenDisconnected(dataSubscription);

      // only initialize elm327 if the needed characteristics are found
      // and listen for incoming data
      CustomLogger.d(
          "Starting ELM327 initialization from _discoverCharacteristicsAndStartElm327");
      await _initializeElm327();
    }
  }

  Future<void> setupConnectedDevice(BluetoothDevice device) async {
    _activeDevice = device;
    CustomLogger.i("Connected to device: ${_activeDevice?.remoteId.str}");
    await _requestMtu(device);
    CustomLogger.d("MTU requested");
    CustomLogger.d("Read rssi timer started (checking every 5 seconds)");
    await _discoverCharacteristicsAndStartElm327(device);
    CustomLogger.d("Characteristics discovered and ELM327 started");
  }

  Future<void> _requestMtu(BluetoothDevice dev) async {
    if (_activeDevice == null) return;
    try {
      await dev.requestMtu(128, predelay: 0);
      CustomLogger.d("MTU after request: ${dev.mtu}");
    } catch (e) {
      return;
    }
  }

  // create all necessary data
  Future<void> _initializeData() async {
    CustomLogger.d('Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    CustomLogger.d('Initialized SharedPreferences');
    await dotenv.load(fileName: ".env");
    targetService = Guid(dotenv.get('TARGET_SERVICE', fallback: ''));
    targetName = dotenv.get("TARGET_ADV_NAME", fallback: "");
    CustomLogger.d('Initialized dotenv');
    try {
      await ObjectBox.create();
      _store = ObjectBox.store;
      CustomLogger.d('Initialized ObjectBox');
    } catch (e) {
      CustomLogger.e('ObjectBox error: $e');
    }
    knownRemoteIds = _prefs.getStringList("knownRemoteIds") ?? [];
    CustomLogger.d('Initialized knownRemoteIds');
    _tripController ??= await TripController.create();
    CustomLogger.d('Initialized TripController');
    _gpsService ??= GpsService();
    CustomLogger.d('Initialized GpsService');
    await VehicleUtils.initializeVehicleModels();
    CustomLogger.d('Initialized VehicleModels');
  }

  // this method is called every minute if and only if the connection state is disconnected
  Future<void> _scanDevices() async {
    if (_connectionState == BluetoothConnectionState.connected) {
      CustomLogger.d("Already connected to a device, can't scan");
      return;
    }
    try {
      CustomLogger.i("Scanning for devices...");
      await FlutterBluePlus.startScan(
          withServices: [targetService],
          withNames: [targetName],
          timeout: const Duration(seconds: 2));
    } catch (e) {
      CustomLogger.e("Error in _scanDevices: $e");
      return;
    }
  }

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
        CustomLogger.d("Starting auto connect to device: $id");
        break;
      } catch (e) {
        CustomLogger.e("Error in _fetchAndConnectToDevices: $e");
        return;
      }
    }
  }

  // --------------------------------------------------------------------------
  // PRIVATE METHODS: Elm327
  // --------------------------------------------------------------------------

  Future<void> _initializeElm327() async {
    if (FlutterBluePlus.connectedDevices.isEmpty) {
      CustomLogger.w("Can't reinitialize ELM327, no connected device");
      return;
    }
    debugPrint("Initializing ELM327");
    // to skip these commands on the next trip
    final bool wasAlreadyInitialized = _activeDevice != null
        ? _prefs.getBool(_activeDevice!.remoteId.str) ?? false
        : false;
    if (!wasAlreadyInitialized) {
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
          CustomLogger.e("Failed to send command: $cmd");
          return;
        }
        if (cmd == "ATZ") {
          await Future.delayed(const Duration(
              milliseconds: 2500)); // ATZ takes longer to process
        } else {
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    } else {
      CustomLogger.i("ELM327 already initialized, skipping setup");
    }
    // elm327 is only considered to be setup here.
    _isElm327Initialized = true;
    if (_activeDevice != null) {
      await _prefs.setBool(_activeDevice!.remoteId.str, _isElm327Initialized);
      CustomLogger.d("ELM327 initialized status saved to shared preferences");
    }
    CustomLogger.i("ELM327 initialized");
    await _startVoltageTimer();

    // check every 3 seconds if the engine is running
    // if it is running, we can start a trip
  }

  Future<void> _startVoltageTimer() async {
    _voltageTimer?.cancel();
    _voltageTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      CustomLogger.d("Calling _voltageTimer");
      try {
        if (_isElm327Initialized) {
          final success = await _sendCommand(voltageCommand);
          if (!success) {
            CustomLogger.e("Failed to send voltage command");
            return;
          }
        }
      } catch (e) {
        CustomLogger.e("Error in _voltageTimer: $e");
      }
    });
  }

  Future<bool> _requestVin() async {
    // keep asking VIN for 5 times, then continue with mileage
    try {
      if (_isElm327Initialized && _vehicleVin == null) {
        CustomLogger.d("Sending VIN request");
        for (int i = 0; i < 5; i++) {
          final success = await _sendCommand(vinCommand);
          if (!success) {
            CustomLogger.w("Failed to send VIN command");
          }
          await Future.delayed(const Duration(seconds: 1));
          if (_vehicleMileage != null) {
            CustomLogger.i("VIN set after $i tries");
            break;
          }
        }
        if (_vehicleVin == null) {
          CustomLogger.fatal("VIN not set after 5 tries");
          return false;
        } else {
          CustomLogger.d("VIN set: $_vehicleVin");
        }
      }
    } catch (e) {
      CustomLogger.fatal("Error in requesting VIN: $e");
      return false;
    }
    return true;
  }

  Future<void> _requestMileage() async {
    try {
      _mileageSendCommandTimer =
          Timer.periodic(const Duration(seconds: 2), (_) async {
        CustomLogger.d("Calling _mileageSendCommandTimer");
        if (_isElm327Initialized) {
          CustomLogger.d("Sending mileage request");
          final success = await _sendCommand(
              VehicleUtils.getVehicleMileageCommand(_vehicleVin!));
          if (!success) {
            CustomLogger.e("Failed to send mileage command");
          }
        }
      });
    } catch (e) {
      CustomLogger.e("Error in requesting mileage: $e");
    }
  }

  Future<void> _startTelemetryCollection() async {
    CustomLogger.d("Starting telemetry collection");
    _startTrip();
    final isVinSet = await _requestVin();
    if (isVinSet) {
      CustomLogger.d("VIN is set, starting mileage request");
      await _requestMileage();
    } else {
      _endTrip();
    }
  }

  // send command to elm327
  Future<bool> _sendCommand(String command) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _activeDevice?.isDisconnecting.first == true) {
      CustomLogger.d("Can't send command, device is disconnected");
      return false;
    }
    CustomLogger.i("Sending command: $command");
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await _writeCharacteristic?.write(bytes, withoutResponse: true);
      CustomLogger.d("Command written: $command");
      return true;
    } catch (e) {
      CustomLogger.e("Error in _sendCommand: $e");
      return false;
    }
  }

  // check if VIN is valid
  bool _checkVin(String vin) {
    if (vin.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      if (vinRegex.hasMatch(vin)) {
        CustomLogger.d("VIN is valid");
        return true;
      }
    }
    CustomLogger.d("VIN is invalid");
    return false;
  }

  // check if mileage is valid
  bool _checkMileage(int mileage) {
    if (mileage >= 0 && mileage <= 2000000) {
      CustomLogger.d("Mileage is valid");
      return true;
    }
    CustomLogger.d("Mileage is invalid");
    return false;
  }

  // manage incoming data from elm327
  void handleReceivedData(List<int> data) {
    // decode it and add it to the buffer because responses can be split into multiple parts
    String incomingData = utf8.decode(data);
    CustomLogger.d("Incoming data: $incomingData");
    _responseBuffer += incomingData;
    int endIndex = _responseBuffer.indexOf(">"); // ">" is the end of a response
    while (endIndex != -1) {
      String completeResponse = _responseBuffer.substring(0, endIndex).trim();
      _responseBuffer = _responseBuffer.substring(endIndex + 1);
      CustomLogger.d("Complete response: $completeResponse");
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
    CustomLogger.d("Cleaned response: $cleanedResponse");

    if (cleanedResponse.isEmpty) return; // unsolicited response, ignore it
    // every mileage response starts with 6210

    // TODO: check if this is working!!!!!!
    if (cleanedResponse.contains("V") && _voltageVal == null) {
      final parts = cleanedResponse.split("V");
      if (parts.isNotEmpty) {
        final voltageString = parts[0];
        // for debugging:
        for (var part in parts) {
          CustomLogger.d("Voltage part: $part");
        }
        final voltageIntValue = int.tryParse(voltageString);
        if (voltageIntValue != null) {
          CustomLogger.d("Voltage: $voltageIntValue");
          _voltageVal = voltageIntValue / 1000;
          if (_voltageVal! >= 13.0) {
            CustomLogger.d(
                "Voltage is at or above 13V, engine is running, cancelling timer");
            CustomLogger.d("Voltage is: $_voltageVal");
            _voltageTimer?.cancel();
            _voltageTimer = null;
            _startTelemetryCollection();
          }
          _voltageTimer?.cancel();
          _voltageTimer = null;
          CustomLogger.d("Voltage: $_voltageVal");
          _startTelemetryCollection();
        }
      }
    }
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
    CustomLogger.d("Calculated VIN: $vin");
    final isVinValid = _checkVin(vin);
    if (isVinValid) {
      _vehicleVin = vin;
      CustomLogger.d("VIN valid and now set to: $_vehicleVin");
    } else {
      CustomLogger.w("VIN is invalid");
    }
  }

  void _handleResponseToMileageCommand(String response) async {
    _tripTimeoutTimer?.cancel();
    final mileage = VehicleUtils.getVehicleKm(_vehicleVin!, response);
    final isMileageValid = _checkMileage(mileage);
    CustomLogger.d("Calculated mileage: $mileage");
    if (isMileageValid) {
      _vehicleMileage = mileage;
      _tripTimeoutTimer = Timer(const Duration(seconds: 10), () async {
        if (_tripController?.currentTrip != null) {
          await _endTrip();
        }
      });
    } else {
      CustomLogger.w("Mileage is invalid");
      if (_tripController?.currentTrip != null) {
        CustomLogger.i("Trip running, cancelling trip...");
        await _endTrip();
      }
    }
  }

  Future<void> _startTrip() async {
    try {
      if (_tripController!.currentTrip == null) {
        try {
          final position = await _gpsService!.currentPosition ??
              _gpsService!.lastKnownPosition;
          CustomLogger.d("Current position: $position");
          _tempLocation = await _gpsService!.getLocationFromPosition(position);
          if (_tempLocation == null || _tempLocation?.street == 'not found') {
            CustomLogger.w("Location not found, checking recent locations");
          }
          CustomLogger.d("Location found: $_tempLocation");
          if (_vehicleVin != null) {
            _tempVehicle = Vehicle.fromVin(_vehicleVin!);
          }
          _tripController!
              .startTrip(_vehicleMileage, _tempVehicle, _tempLocation);
        } catch (e) {
          CustomLogger.e("Error in starting trip: $e");
        }

        CustomLogger.i(_tripController!.currentTrip.toString());
        CustomLogger.i("Fahrtaufzeichnung hat begonnen");
        updateNotificationText("Fahrtaufzeichnung", "Die Fahrt hat begonnen");
      } else {
        CustomLogger.fatal("Trip already running");
      }
    } catch (e, stackTrace) {
      CustomLogger.e("Error in _startTrip: $e");
      CustomLogger.e(stackTrace.toString());
    }
  }

  Future<void> _endTrip() async {
    if (_tripController!.currentTrip == null) {
      CustomLogger.fatal("No trip to end");
      return;
    }
    try {
      final endPosition = await _gpsService!.currentPosition;
      CustomLogger.d("End position: $endPosition");
      _tempLocation = await _gpsService!.getLocationFromPosition(endPosition);
      CustomLogger.d("New Location found: $_tempLocation");
      _tripController!.endTrip(_tempLocation, _vehicleMileage);
    } catch (e) {
      debugPrint("Error in _endTelemetryCollection: $e");
    }
    updateNotificationText("Fahrt beendet", "Die Fahrt wurde beendet");
    _cancelALlTimersExceptBleDisconnect();
    CustomLogger.d("Cancelled all Timers on trip end");
    _resetAllTripVariables();
    await _startVoltageTimer();
    CustomLogger.d("Resetted all trip variables on trip end");
  }
}
