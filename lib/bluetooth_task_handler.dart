import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:driver_logbook/controllers/trip_controller.dart';
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
import 'package:driver_logbook/utils/custom_log.dart';

// maybe write a separate task handler for ios
// if it is even possible to run a task like that on ios

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BluetoothTaskHandler());
}

class BluetoothTaskHandler extends TaskHandler {
  // Data
  late Store _store; // objectbox store for storing trips
  TripController? _tripController; // trip controller for managing trips
  late SharedPreferences
      _prefs; // shared preferences for storing known remote ids and category index

  // Bluetooth
  BluetoothDevice? _connectedDevice; // connected device
  BluetoothCharacteristic? _writeCharacteristic; // data to send to elm327
  BluetoothCharacteristic? _notifyCharacteristic; // data to receive from elm327
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected; // default connection state
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription; // for handling connection states
  StreamSubscription<OnReadRssiEvent>?
      _rssiStreamSubscription; // rssi stream to handle readings
  final int _disconnectRssiThreshold = -85; // threshold to disconnect a device
  final int _goodRssiThreshold =
      -75; // threshold to cancel a pending disconnect
  // static const Duration _rssiDuration =
  //     Duration(seconds: 10); // interval to read rssi
  List<String> knownRemoteIds = []; // list of known remote ids to connect to
  Timer? _rssiDisconnectTimer; // timer to disconnect a device if rssi is low
  Timer? _bleDisconnectTimer; // timer to scan for devices if disconnected
  int? _tripCategoryIndex; // index of the trip category
  // StreamSubscription<List<int>>?
  //     _dataSubscription; // for obversing incoming data from elm327
  StreamSubscription<List<ScanResult>>?
      _scanResultsSubscription; //  for handling scan results

  // misc
  GpsService? _gpsService; // used for getting the location
  String? _vehicleVin; // used for saving the vin
  int? _vehicleMileage; // used for saving and tracking the mileage
  Timer?
      _mileageSendCommandTimer; // used for sending mileage requests continuously
  Timer? _vinSendCommandTimer; // used for sending vin requests continuously
  Timer? _dataTimeoutTimer; // used for ending the trip if no data is received
  Timer?
      _elm327Timer; // used for reinitializing elm327 if a consecutive trip happens
  Timer? _readRssiTimer; // used for reading the rssi continuously
  bool _isElm327Initialized = false; // default state of elm327
  Timer? _tripTimeoutTimer; // used for ending the trip if no data is received
  Timer? _tripCancelTimer; // used for cancelling the trip if connection is lost

  TripLocation _tempLocation = TripLocation(
      street: "Unbekannt",
      city: "Unbekannt",
      postalCode: "Unbekannt"); // default location if no location is found
  String _responseBuffer = ''; // buffer for incoming data from the elm327
  static const String vinCommand =
      "0902"; // standardized obd2 command for requesting the vin

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
    // CustomLogger.d('[BluetoothTaskHandler] onRepeatEvent'); // debug
    final tripsToTransmit = TripRepository.getFinishedAndCancelledTrips();
    if (tripsToTransmit.isEmpty) {
      CustomLogger.d("No trips to transmit");
      return;
    }
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
    _tripController = null;
    _gpsService = null;
    _vehicleMileage = null;
    _vehicleVin = null;
    _isElm327Initialized = false;
    _tempLocation = TripLocation(
        street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
    _responseBuffer = '';
    _store.close();
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _connectionState = BluetoothConnectionState.disconnected;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _rssiStreamSubscription?.cancel();
    _rssiStreamSubscription = null;
    _rssiDisconnectTimer?.cancel();
    _rssiDisconnectTimer = null;
    _bleDisconnectTimer?.cancel();
    _bleDisconnectTimer = null;
    _tripTimeoutTimer?.cancel();
    _tripTimeoutTimer = null;
    _tripCancelTimer?.cancel();
    _tripCancelTimer = null;
    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
    if (_connectedDevice != null) {
      debugPrint("Disconnecting device on destroy");
      await _connectedDevice!.disconnectAndUpdateStream();
      _connectedDevice = null;
    }
  }

  void _cancelALlTimer() {
    _vinSendCommandTimer?.cancel();
    _vinSendCommandTimer = null;
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

    _bleDisconnectTimer = Timer(const Duration(seconds: 10), () {
      CustomLogger.d("BLE disconnect timer started");
      if (_connectionState == BluetoothConnectionState.disconnected) {
        CustomLogger.d("Starting scan after 10 seconds and no connection");
        _scanDevices();
      }
    });

    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      _connectionState = event.connectionState;
      CustomLogger.i("Connection state: $_connectionState");
      if (event.connectionState == BluetoothConnectionState.connected) {
        if (_connectedDevice != null) {
          CustomLogger.w(
              "Already connected to a device: ${_connectedDevice?.remoteId.str}");
          return;
        }
        // initialize device on connection
        _connectedDevice = event.device;
        CustomLogger.i(
            "Connected to device: ${_connectedDevice?.remoteId.str}");
        await _requestMtu(event.device);
        CustomLogger.d("MTU requested");
        _readRssiTimer = Timer.periodic(
            const Duration(seconds: 5), (_) => _connectedDevice?.readRssi());
        CustomLogger.d("Read rssi timer started (checking every 5 seconds)");
        await _discoverCharacteristicsAndStartElm327(event.device);
        CustomLogger.d("Characteristics discovered and ELM327 started");
        if (_elm327Timer != null || _elm327Timer?.isActive == true) {
          _elm327Timer?.cancel();
          CustomLogger.d("Cancelled ELM327 timer");
        }
        _elm327Timer = Timer.periodic(const Duration(seconds: 15), (_) {
          CustomLogger.d("Calling ELM327 timer");
          if (!_isElm327Initialized) {
            CustomLogger.d(
                "15 Seconds over and not initialized, trying to reinitialize ELM327");
            _initializeElm327();
          }
        });
        _bleDisconnectTimer?.cancel();
        _bleDisconnectTimer = null;
        CustomLogger.d("BLE disconnect timer cancelled on connection");
      } else {
        // device disocnnected
        // _tripCancelTimer?.cancel();
        // CustomLogger.d("Trip cancel timer cancelled");
        // if (_tripController?.currentTrip != null) {
        //   Future.delayed(const Duration(seconds: 15), () {
        //     CustomLogger.d(
        //         "Waiting 15 seconds to check if device is still disconnected");
        //     if (_connectionState == BluetoothConnectionState.disconnected) {
        //       CustomLogger.i("Device is still disconnected, cancelling trip");
        //       _endTrip(TripStatus.cancelled);
        //     }
        //   });
        // }
        _cancelALlTimer();
        _connectedDevice = null;
        _writeCharacteristic = null;
        _notifyCharacteristic = null;
        _isElm327Initialized = false;
        _vehicleMileage = null;
        _vehicleVin = null;
        CustomLogger.i(
            "Setting all variables to null on disconnection: $_vehicleVin, $_vehicleMileage");
        _bleDisconnectTimer = Timer(const Duration(seconds: 10), () {
          CustomLogger.d(
              "BLE disconnect timer started again after disconnection");
          if (_connectionState == BluetoothConnectionState.disconnected) {
            CustomLogger.d("Starting scan after 10 seconds and no connection");
            _scanDevices();
          }
        });
        // reconnect to known devices
        Future.delayed(const Duration(seconds: 10), () async {
          CustomLogger.d("Reconnecting to known devices after 10 seconds");
          await _fetchAndConnectToDevices();
        });
      }
    });
    // use a subscription to update the scan results and save them
    _scanResultsSubscription ??=
        FlutterBluePlus.onScanResults.listen((results) {
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
        _fetchAndConnectToDevices();
      }
    });
    CustomLogger.d(
        "Fetching and connecting to devices in _initializeBluetooth");
    _fetchAndConnectToDevices();

    // keep track of the rssi to disconnect a device
    // best case is: a ble connection only establishes when the driver is in his car
    _rssiStreamSubscription ??=
        FlutterBluePlus.events.onReadRssi.listen((event) {
      if (event.device.remoteId == _connectedDevice?.remoteId) {
        final currentRssi = event.rssi;
        CustomLogger.i("Current RSSI: $currentRssi");

        // If rssi is below -85 for 10+ seconds, disconnect
        if (currentRssi < _disconnectRssiThreshold) {
          CustomLogger.i("RSSI below -85, starting disconnect timer");
          // toggle on:
          _rssiDisconnectTimer = Timer(const Duration(seconds: 10), () {
            _connectedDevice?.disconnectAndUpdateStream();
            CustomLogger.i("Device disconnected due to low RSSI");
          });
        }
        // If rssi climbs back above -75, cancel the pending disconnect
        else if (currentRssi > _goodRssiThreshold &&
            _rssiDisconnectTimer?.isActive == true) {
          _rssiDisconnectTimer!.cancel();
          _rssiDisconnectTimer = null;
          CustomLogger.i("RSSI above -75, cancelling disconnect timer");
        }
      }
    });
    CustomLogger.d("_initializeBluetooth completed");
  }

  void _initializeTime() async {
    await initializeDateFormatting('de_DE');
    Intl.defaultLocale = 'de_DE';
  }

  Future<void> _discoverCharacteristicsAndStartElm327(
      BluetoothDevice device) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
      CustomLogger.d("Can't discover characteristics, device is disconnected");
      return;
    }
    final Guid targetService = Guid(dotenv.get('TARGET_SERVICE', fallback: ''));
    CustomLogger.d("Discovering characteristics for service: $targetService");
    List<BluetoothService> services =
        await _connectedDevice!.discoverServices();
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
      _connectedDevice?.cancelWhenDisconnected(dataSubscription);

      // only initialize elm327 if the needed characteristics are found
      // and listen for incoming data
      CustomLogger.d(
          "Starting ELM327 initialization from _discoverCharacteristicsAndStartElm327");
      await _initializeElm327();
    }
  }

  Future<void> _requestMtu(BluetoothDevice dev) async {
    if (_connectionState == BluetoothConnectionState.disconnected) return;
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
    _tripController ??= TripController();
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
          withServices: [Guid(dotenv.get('TARGET_SERVICE', fallback: ''))],
          withNames: [dotenv.get("TARGET_ADV_NAME", fallback: "")],
          timeout: const Duration(seconds: 2));
    } catch (e) {
      CustomLogger.e("Error in _scanDevices: $e");
      return;
    }
  }

  Future<void> _fetchAndConnectToDevices() async {
    _prefs.reload();
    CustomLogger.d("Fetching and connecting to devices...");
    CustomLogger.i("Known remote ids: $knownRemoteIds");
    if (knownRemoteIds.isEmpty) {
      CustomLogger.d("No known remote ids");
      return;
    }

    if (_connectedDevice != null) {
      CustomLogger.d(
          "Already connected to a device: ${_connectedDevice?.remoteId.str}");
      return;
    }
    for (var id in knownRemoteIds) {
      // if a device is already connected, prevent connecting to new devices
      if (_connectionState == BluetoothConnectionState.connected) {
        // needed for mid loop handling to avoid race conditions
        CustomLogger.d("Already connected to a device, can't connect");
        return;
      }
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
    if (_isElm327Initialized ||
        _connectionState != BluetoothConnectionState.connected) {
      CustomLogger.d("Can't reinitialize ELM327 again (race condition)");
      return;
    }
    debugPrint("Initializing ELM327");
    // TODO: maybe save initialized elm327 in shared preferences
    // to skip these commands on the next trip
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
        await Future.delayed(
            const Duration(milliseconds: 2500)); // ATZ takes longer to process
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    // elm327 is only considered to be setup here.
    _isElm327Initialized = true;
    CustomLogger.i("ELM327 initialized");
    _vinSendCommandTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      CustomLogger.d("Calling _vinSendCommandTimer");
      try {
        if (_isElm327Initialized && _vehicleVin == null) {
          CustomLogger.d("Sending VIN request");
          await _sendCommand(vinCommand);
        } else {
          _vinSendCommandTimer?.cancel();
          _vinSendCommandTimer = null;
          CustomLogger.d("Cancelled _vinSendCommandTimer");
          _mileageSendCommandTimer =
              Timer.periodic(const Duration(seconds: 4), (_) async {
            CustomLogger.d("Calling _mileageSendCommandTimer");
            try {
              if (_isElm327Initialized && _vehicleVin != null) {
                CustomLogger.d("Sending mileage request");
                await _sendCommand(
                    VehicleUtils.getVehicleMileageCommand(_vehicleVin!));
              }
            } catch (e) {
              CustomLogger.e("Error in _mileageSendCommandTimer: $e");
            }
          });
        }
      } catch (e) {
        CustomLogger.e("Error in _vinSendCommandTimer: $e");
      }
    });
  }

  // send command to elm327
  Future<bool> _sendCommand(String command) async {
    if (_connectionState == BluetoothConnectionState.disconnected ||
        await _connectedDevice?.isDisconnecting.first == true) {
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
    CustomLogger.d("Cleaned response: $cleanedResponse");

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
      CustomLogger.d("Mileage valid and now set to: $_vehicleMileage");
      if (_tripController?.currentTrip == null) {
        CustomLogger.i("Trip not running, starting trip...");
        await _startTrip();
      }

      _tripTimeoutTimer = Timer(const Duration(seconds: 10), () async {
        if (_tripController?.currentTrip != null) {
          await _endTrip(TripStatus.finished);
        }
      });
    } else {
      CustomLogger.w("Mileage is invalid");
      if (_tripController?.currentTrip != null) {
        CustomLogger.i("Trip running, cancelling trip...");
        await _endTrip(TripStatus.cancelled); // Added await
      }
    }
  }

  Future<void> _startTrip() async {
    try {
      if (_tripController!.currentTrip == null) {
        try {
          final position = await _gpsService!.currentPosition;
          CustomLogger.d("Current position: $position");
          _tempLocation = await _gpsService!.getLocationFromPosition(position);
          CustomLogger.d("Location found: $_tempLocation");
        } catch (e) {
          CustomLogger.e("Error in _startTrip: $e");
          _tempLocation = TripLocation(
              street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
        }
        _tripController!.startTrip(
            _vehicleMileage!, Vehicle.fromVin(_vehicleVin!), _tempLocation);
        CustomLogger.i(_tripController!.currentTrip.toString());
        CustomLogger.i("Fahrtaufzeichnung hat begonnen");
        updateNotificationText("Fahrtaufzeichnung", "Die Fahrt hat begonnen");
      }
    } catch (e, stackTrace) {
      CustomLogger.e("Error in _startTrip: $e");
      CustomLogger.e(stackTrace.toString());
    }
  }

  Future<void> _endTrip(TripStatus status) async {
    if (_tripController!.currentTrip == null) {
      CustomLogger.w("No trip to end");
      return;
    }
    try {
      final endPosition = await _gpsService!.currentPosition;
      CustomLogger.d("End position: $endPosition");
      _tempLocation = await _gpsService!.getLocationFromPosition(endPosition);
      CustomLogger.d("New Location found: $_tempLocation");
    } catch (e) {
      debugPrint("Error in _endTelemetryCollection: $e");
      _tempLocation = TripLocation(
          street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
    }
    _tripController!.endTrip(_tempLocation, _vehicleMileage!, status);
    CustomLogger.i(_tripController!.currentTrip.toString());
    CustomLogger.i("Fahrt beendet mit Status: $status");
    updateNotificationText(
        "Fahrt beendet mit Status: $status", "Die Fahrt wurde beendet");
    _vehicleVin = null;
    _vehicleMileage = null;
    CustomLogger.i("Resetted vin and mileage: $_vehicleVin, $_vehicleMileage");
    _mileageSendCommandTimer?.cancel();
    _mileageSendCommandTimer = null;
    CustomLogger.d("Cancelled _mileageSendCommandTimer");
    // needed for reinitializing elm327
    _isElm327Initialized = false;
    CustomLogger.d("Set ELM327 to false after trip end: $_isElm327Initialized");
  }
}
