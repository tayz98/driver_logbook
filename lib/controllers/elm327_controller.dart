import 'dart:async';
import 'dart:convert';
import 'package:driver_logbook/controllers/trip_controller.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/vehicle.dart';
import 'package:driver_logbook/services/gps_service.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:driver_logbook/utils/vehicle_utils.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Elm327Controller {
  final BluetoothDevice _device;
  get deviceId => _device.remoteId;
  final BluetoothCharacteristic _writeCharacteristic;
  // ignore: unused_field
  final BluetoothCharacteristic _notifyCharacteristic;
  bool _isInitialized = false;
  bool _isTripInProgress = false;
  bool get isTripInProgress => _isTripInProgress;

  // telemetry-related:
  String? _vehicleVin; // used for saving the vin
  int? _vehicleMileage; // used for saving and tracking the mileage
  double?
      _voltageVal; // used for checking voltage of the vehicle (engine runnning)
  TripLocation? _tempLocation;
  Vehicle? _tempVehicle;
  final String vinCommand =
      "0902"; // standardized obd2 command for requesting the vin
  final String voltageCommand =
      "ATRV"; // ELM327 system command for checking vehicle voltage
  Timer? _voltageTimer; // timer to read the voltage of the vehicle
  Timer? _tripTimeoutTimer; // used for ending the trip if no data is received
  Timer?
      _mileageSendCommandTimer; // used for sending mileage requests continuously
  String _responseBuffer = ''; // buffer for incoming data from the elm327
  final TripController? _tripController; // controller for managing trips
  final GpsService? _gpsService; // used for getting the location

  Elm327Controller({
    required BluetoothDevice device,
    required BluetoothCharacteristic writeCharacteristic,
    required BluetoothCharacteristic notifyCharacteristic,
  })  : _device = device,
        _notifyCharacteristic = notifyCharacteristic,
        _writeCharacteristic = writeCharacteristic,
        _tripController = TripController(),
        _gpsService = GpsService();

  Future<bool> initialize() async {
    if (_isInitialized) {
      CustomLogger.w("ELM327 already initialized");
      return true;
    }
    final prefs = await SharedPreferences.getInstance();

    final bool isAlreadyInitialized =
        prefs.getBool(_device.remoteId.str) ?? false;

    if (!isAlreadyInitialized) {
      List<String> initCommands = [
        // "ATZ", // Reset ELM327
        // "ATD", // reset defaults
        "ATSP0", // Set Protocol to Automatic
        "ATE0", // Echo Off
        // "ATL0", // Linefeeds Off
        // "ATS0", // Spaces Off
        "ATH1", // Headers On
        "ATSH 7E0", // Set Header to 7E0
      ];
      for (String cmd in initCommands) {
        bool success = await sendCommand(cmd);
        if (!success) {
          CustomLogger.e("Failed to send command: $cmd");
          return false;
        } else {
          // TODO: test if this short delay is not causing any issues
          await Future.delayed(const Duration(milliseconds: 1100));
        }
      }
    } else {
      CustomLogger.i("ELM327 already initialized, skipping setup");
    }
    _isInitialized = true;
    await prefs.setBool(_device.remoteId.str, _isInitialized);
    // problem:
    // if the adapter is taken out of the car, it will reset and needs a new initialization
    // so, saving the initialization status to shared preferences might not be the best idea
    // on the other hand, initializing the adapter every time a connection is established
    // takes too long and is not practical
    // i could try tuning the initialization commands to make it faster
    // but from my experience, the adapter needs at least 3 seconds to respond to the commands
    CustomLogger.d("ELM327 initialized status saved to shared preferences");
    CustomLogger.i("ELM327 initialized");
    return _isInitialized;
  }
  // send command to elm327

  Future<void> dispose() async {
    if (_isTripInProgress) {
      await endTrip();
    }
    _isInitialized = false;
    _vehicleVin = null;
    _vehicleMileage = null;
    _voltageVal = null;
    _tempLocation = null;
    _tempVehicle = null;
    _responseBuffer = '';
    _voltageTimer?.cancel();
    _tripTimeoutTimer?.cancel();
    _mileageSendCommandTimer?.cancel();
    CustomLogger.i("ELM327 disposed");
  }

  Future<void> _startTrip() async {
    _isTripInProgress = true;
    try {
      if (_tripController!.currentTrip == null) {
        try {
          final position = await _gpsService!.currentPosition ??
              _gpsService.lastKnownPosition;
          CustomLogger.d("Current position: $position");
          _tempLocation = await _gpsService.getLocationFromPosition(position);
          if (_tempLocation == null || _tempLocation?.street == 'not found') {
            CustomLogger.w("Location not found, checking recent locations");
          }
          CustomLogger.d("Location found: $_tempLocation");
          if (_vehicleVin != null) {
            _tempVehicle = Vehicle.fromVin(_vehicleVin!);
          }
          _tripController.startTrip(
              _vehicleMileage, _tempVehicle, _tempLocation);
        } catch (e) {
          CustomLogger.e("Error in starting trip: $e");
        }

        CustomLogger.i(_tripController.currentTrip.toString());
        CustomLogger.i("Fahrtaufzeichnung hat begonnen");
        _updateForegroundNotificationText(
            "Fahrtaufzeichnung", "Die Fahrt hat begonnen");
      } else {
        CustomLogger.fatal("Trip already running");
      }
    } catch (e, stackTrace) {
      CustomLogger.e("Error in _startTrip: $e");
      CustomLogger.e(stackTrace.toString());
    }
  }

  void _updateForegroundNotificationText(String title, String content) {
    FlutterForegroundTask.updateService(
        notificationTitle: title, notificationText: content);
  }

  Future<void> endTrip() async {
    _mileageSendCommandTimer?.cancel();
    _isTripInProgress = false;
    if (_tripController!.currentTrip == null) {
      CustomLogger.fatal("No trip to end");
      return;
    }
    try {
      final endPosition =
          await _gpsService!.currentPosition ?? _gpsService.lastKnownPosition;
      CustomLogger.d("End position: $endPosition");
      _tempLocation = await _gpsService.getLocationFromPosition(endPosition);
      CustomLogger.d("New Location found: $_tempLocation");
      _tripController.endTrip(_tempLocation, _vehicleMileage);
    } catch (e) {
      CustomLogger.e("Error in _endTrip: $e");
    }
    CustomLogger.d("Cancelled all Timers on trip end");
    _updateForegroundNotificationText(
        "Fahrtaufzeichnung", "Die Fahrt hat geendet");
    // _resetAllTripVariables();
    await startVoltageTimer();
    // after trip ends, start voltage timer again
    // to check if a consecutive trip is started
    CustomLogger.d("Resetted all trip variables on trip end");
  }

  Future<bool> sendCommand(String command) async {
    if (_device.isDisconnected) {
      CustomLogger.w("Device is not connected, can't send command!");
      return false;
    }
    CustomLogger.i("Sending command: $command");
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    CustomLogger.d("Bytes sent: $bytes");
    try {
      await _writeCharacteristic.write(bytes, withoutResponse: true);
      CustomLogger.d("Command written: $command");
      return true;
    } catch (e) {
      CustomLogger.e("Error in _sendCommand: $e");
      return false;
    }
  }

  // manage incoming data from elm327
  void handleReceivedData(List<int> data) {
    // decode it and add it to the buffer because responses can be split into multiple parts
    String incomingData = utf8.decode(data);
    // CustomLogger.d("Incoming data: $incomingData");
    _responseBuffer += incomingData;
    int endIndex = _responseBuffer.indexOf(">"); // ">" is the end of a response
    while (endIndex != -1) {
      String completeResponse = _responseBuffer.substring(0, endIndex).trim();
      _responseBuffer = _responseBuffer.substring(endIndex + 1);
      // CustomLogger.d("Complete response: $completeResponse");
      _processCompleteResponse(completeResponse);
      endIndex = _responseBuffer.indexOf(">");
    }
  }

  final List<String> unwantedStrings = [
    "]",
    "[",
    ">",
    "\n",
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
  void _processCompleteResponse(String response) async {
    // remove all unnecessary characters or words
    String cleanedResponse = response;
    for (String str in unwantedStrings) {
      cleanedResponse = cleanedResponse.replaceAll(str, "");
    }
    cleanedResponse = cleanedResponse.replaceAll(RegExp(r"\s+"), "").trim();
    CustomLogger.d("Cleaned response: $cleanedResponse");

    if (cleanedResponse.isEmpty) return; // unsolicited response, ignore it
    // every mileage response starts with 6210

    if (cleanedResponse.contains("V")) {
      CustomLogger.d("Voltage command response");
      final parts = cleanedResponse.split("V");
      if (parts.isNotEmpty) {
        final voltageString = parts.first;
        // for debugging:
        for (var part in parts) {
          CustomLogger.d("Voltage part: $part");
        }
        final voltageIntValue = int.tryParse(voltageString);
        if (voltageIntValue != null) {
          _voltageVal = voltageIntValue / 10;
          CustomLogger.d("Voltage is: $_voltageVal");
          final rssi = await _device.readRssi();
          if (_voltageVal! >= 13.0 && rssi >= -70) {
            CustomLogger.i(
                "Voltage is at or above 13V, engine is running, and signal strength is good");
            CustomLogger.d("Cancelling voltage timer and starting telemetry");
            _voltageTimer?.cancel();
            _voltageTimer = null;
            await _startTelemetryCollection();
          }
        } else {
          CustomLogger.w("Voltage int couldn't be parsed is null");
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

  Future<void> startVoltageTimer() async {
    _voltageTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      CustomLogger.d("Calling _voltageTimer");
      try {
        await sendCommand(voltageCommand);
      } catch (e) {
        CustomLogger.e("Error in _voltageTimer: $e");
      }
    });
  }

  Future<bool> _requestVin() async {
    if (_voltageVal == null) {
      CustomLogger.fatal("Voltage is null, starting voltage timer");
      return false;
    }
    const int maxTries = 10;
    try {
      if (_isInitialized && _vehicleVin == null) {
        CustomLogger.d("Sending VIN request");
        for (int i = 0; i < maxTries; i++) {
          final success = await sendCommand(vinCommand);
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
          CustomLogger.fatal("VIN not set after $maxTries tries");
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
    if (_vehicleVin == null) {
      CustomLogger.fatal("VIN is null, can't request mileage");
      return;
    }
    try {
      _mileageSendCommandTimer =
          Timer.periodic(const Duration(seconds: 3), (_) async {
        CustomLogger.d("Calling _mileageSendCommandTimer");
        if (_isInitialized) {
          CustomLogger.d("Sending mileage request");
          final success = await sendCommand(
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
    if (_isTripInProgress) {
      CustomLogger.i("Trip already running, skipping telemetry collection");
      return;
    }
    CustomLogger.d("Starting telemetry collection");
    await _startTrip();
    final isVinSet = await _requestVin();
    if (isVinSet) {
      // VIN is a required field for requesting mileage (see vehicle_utils.dart)
      CustomLogger.d("VIN is set, starting mileage request");
      await _requestMileage();
    } else {
      endTrip();
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

  void _handleResponseToMileageCommand(String response) async {
    CustomLogger.d("Handling mileage response");
    _tripTimeoutTimer?.cancel();
    CustomLogger.d("Trip timeout timer cancelled");
    final mileage = VehicleUtils.getVehicleKm(_vehicleVin!, response);
    final isMileageValid = _checkMileage(mileage);

    if (isMileageValid) {
      _vehicleMileage = mileage;
      CustomLogger.i("Mileage read: $_vehicleMileage");
      CustomLogger.d("Trip timeout timer called");
      _tripTimeoutTimer = Timer(const Duration(seconds: 10), () async {
        if (_tripController?.currentTrip != null) {
          CustomLogger.i("Trip timeout, ending trip...");
          await endTrip();
        }
      });
    } else {
      CustomLogger.w("Mileage is invalid");
      if (_tripController?.currentTrip != null) {
        CustomLogger.i("Trip running, cancelling trip...");
        await endTrip();
      }
    }
  }
}
