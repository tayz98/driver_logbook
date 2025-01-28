import 'dart:async';
import 'dart:convert';
import 'package:driver_logbook/controllers/trip_controller.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/vehicle.dart';
import 'package:driver_logbook/services/gps_service.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:driver_logbook/utils/help.dart';
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
  // just a getter for task handler and to simplify the code
  bool get isTripInProgress => TripController().currentTrip != null;
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

  Elm327Controller({
    required BluetoothDevice device,
    required BluetoothCharacteristic writeCharacteristic,
    required BluetoothCharacteristic notifyCharacteristic,
  })  : _device = device,
        _notifyCharacteristic = notifyCharacteristic,
        _writeCharacteristic = writeCharacteristic;

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
        // TODO: maybe ATSP0 is not needed
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
          // this needs to be at least 4000ms for the commands to register
          await Future.delayed(const Duration(milliseconds: 4000));
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
    // takes too long (round about 4s per init command) and is not practical
    // a solution could be: if no response is received after a certain time
    // it means that the adapter has been reset and needs to be initialized again
    CustomLogger.d("ELM327 initialized status saved to shared preferences");
    CustomLogger.i("ELM327 initialized");
    return _isInitialized;
  }
  // send command to elm327

  // reset trip variables and timers
  Future<void> dispose() async {
    if (isTripInProgress) {
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
    _tripTimeoutTimer = null;
    _mileageSendCommandTimer?.cancel();
    _mileageSendCommandTimer = null;
    CustomLogger.i("ELM327 disposed");
  }

  // initiate a trip
  Future<void> _startTrip() async {
    if (isTripInProgress) {
      // flag to prevent race conditions
      CustomLogger.w("Trip already running, not starting a new one");
      CustomLogger.w(
          "Variables - Trip in Progress: $isTripInProgress, current trip: ${TripController().currentTrip}");
      return;
    }
    // if no trip is running, start a new one
    if (TripController().currentTrip == null) {
      try {
        // get location
        final position = await GpsService().currentPosition;
        CustomLogger.d("Current position: $position");
        _tempLocation = await GpsService().getLocationFromPosition(position);
        if (_tempLocation == null || _tempLocation?.street == 'not found') {
          CustomLogger.w("Location not found");
          final lastKnownPosition = await GpsService().lastKnownPosition;
          if (lastKnownPosition != null) {
            _tempLocation =
                await GpsService().getLocationFromPosition(lastKnownPosition);
          }
          CustomLogger.d("Last known position: $lastKnownPosition");
        }
        CustomLogger.d("Location found: $_tempLocation");
        if (_vehicleVin != null) {
          // create a vehicle with informations from the VIN
          _tempVehicle = Vehicle.fromVin(_vehicleVin!);
        }
        // finally start a trip
        TripController()
            .startTrip(_vehicleMileage, _tempVehicle, _tempLocation);
      } catch (e) {
        // any error here that prevents the trip from starting
        CustomLogger.e("Error in starting trip: $e");
      }

      if (TripController().currentTrip != null) {
        // if a trip is started, log it
        CustomLogger.i(
            "Started trip with: ${jsonEncode(TripController().currentTrip!.toJson())}");
        // CustomLogger.i(_tripController!.currentTrip!.toJson());
        CustomLogger.i("Fahrtaufzeichnung hat begonnen");
        _updateForegroundNotificationText(
            "Fahrtaufzeichnung", "Die Fahrt hat begonnen");
      }
    }
  }

  void _updateForegroundNotificationText(String title, String content) {
    FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: Helper.formatDateString(
            content + DateTime.now().toIso8601String()));
  }

  // end a trip
  Future<void> endTrip() async {
    if (!isTripInProgress) {
      CustomLogger.w("No trip to end");
      CustomLogger.d(
          "Variables - Trip in Progress: $isTripInProgress, current trip: ${TripController().currentTrip}");
      return;
    }
    try {
      final endPosition = await GpsService().currentPosition;
      CustomLogger.d("End position: $endPosition");
      _tempLocation = await GpsService().getLocationFromPosition(endPosition);
      if (_tempLocation == null || _tempLocation?.street == 'not found') {
        CustomLogger.w("End location not found");
        final lastKnownPosition = await GpsService().lastKnownPosition;
        if (lastKnownPosition != null) {
          _tempLocation =
              await GpsService().getLocationFromPosition(lastKnownPosition);
        }
        CustomLogger.d("Last known position: $lastKnownPosition");
      }
      CustomLogger.d("New Location found: $_tempLocation");
      TripController().endTrip(_tempLocation, _vehicleMileage);
    } catch (e) {
      CustomLogger.e("Error in _endTrip: $e");
    }
    CustomLogger.d("Cancelled all Timers on trip end");
    _updateForegroundNotificationText(
        "Fahrtaufzeichnung beendet", "Die Fahrt wurde beendet");
    await dispose();
    CustomLogger.d("Resetted all trip variables on trip end");
    await startVoltageTimer();
    // after trip ends, start voltage timer again
    // to check if a consecutive trip is started
  }

  // send a command to the elm327
  Future<bool> sendCommand(String command) async {
    CustomLogger.i("Sending command: $command");
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      if (_device.isDisconnected) {
        CustomLogger.w("Device is not connected, can't send command: $command");
        return false;
      }
      await _writeCharacteristic.write(bytes, withoutResponse: true);
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

    if (cleanedResponse.contains("V")) {
      await _handleResponseToVoltCommand(response);
    }
    if (cleanedResponse.contains("6210")) {
      // startsWith doesn't work for some reason, that's why contains is used
      // update: should be working by now, but doesn't matter right now
      await _handleResponseToMileageCommand(cleanedResponse);
    }

    // 7E8 is the device id, 10 is the FF,
    //14 is the length of the response (20 bytes),
    //49 is the answer to the mode 09
    if (cleanedResponse.contains("7E8101449")) {
      // startsWith doesn't work here too
      // update: should be working by now, but doesn't matter right now
      _handleResponseToVinCommand(cleanedResponse);
    }
  }

  Future<void> _handleResponseToVoltCommand(String response) async {
    CustomLogger.d("Voltage command response");
    final parts = response.split("V");
    if (parts.isNotEmpty) {
      final voltageString = parts.first;
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
        CustomLogger.w("Voltage int couldn't be parsed, is null");
      }
    }
  }

  void _handleResponseToVinCommand(String response) {
    if (_vehicleVin != null) {
      CustomLogger.w("VIN already set, skipping VIN response handle");
      return;
    }
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

  Future<void> _handleResponseToMileageCommand(String response) async {
    CustomLogger.d("Handling mileage response");

    final mileage = VehicleUtils.getVehicleKm(_vehicleVin!, response);
    CustomLogger.i("Mileage response: $mileage");
    final isMileageValid = _checkMileage(mileage);

    if (isMileageValid) {
      _tripTimeoutTimer?.cancel();
      CustomLogger.d("Trip timeout timer cancelled");
      _vehicleMileage = mileage;
      CustomLogger.d("Trip timeout timer called");
      _tripTimeoutTimer = Timer(const Duration(seconds: 10), () async {
        CustomLogger.d("Trip timeout has lapsed");
        _mileageSendCommandTimer?.cancel();
        if (isTripInProgress) {
          CustomLogger.i("Trip timeout, ending trip...");
          try {
            await endTrip();
          } catch (e) {
            CustomLogger.e("Error in trip timeout: $e");
          }
        } else {
          CustomLogger.w("Trip already ended, skipping trip timeout");
        }
      });
    } else {
      CustomLogger.w("Mileage is invalid");
      if (isTripInProgress) {
        CustomLogger.i("Trip running, cancelling trip...");
        await endTrip();
      }
    }
  }

  // runs always before a trip starts
  Future<void> startVoltageTimer() async {
    _voltageTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      CustomLogger.d("Calling _voltageTimer");
      try {
        if (_device.isDisconnected) {
          CustomLogger.w("Device is not connected, can't check voltage");
          _voltageTimer?.cancel();
          _voltageTimer = null;
          return;
        }
        await sendCommand(voltageCommand);
      } catch (e) {
        CustomLogger.e("Error in _voltageTimer: $e");
      }
    });
  }

  Future<bool> _requestVin() async {
    if (_voltageVal == null) {
      CustomLogger.fatal("Voltage is null, can't request VIN");
      return false;
    }
    const int maxTries = 10;
    try {
      if (_device.isDisconnected) {
        CustomLogger.w("Device is not connected, can't request VIN");
        return false;
      }
      if (_vehicleVin == null) {
        CustomLogger.d("Sending VIN request");
        for (int i = 0; i < maxTries; i++) {
          final success = await sendCommand(vinCommand);
          if (!success) {
            CustomLogger.w("Failed to send VIN command");
          }
          if (_vehicleVin != null) {
            CustomLogger.i("VIN set after $i tries");
            break;
          }
        }
        if (_vehicleVin == null) {
          CustomLogger.fatal("VIN not set after $maxTries tries");
          return false;
        } else {
          CustomLogger.d("VIN: $_vehicleVin");
        }
      }
    } catch (e) {
      CustomLogger.fatal("Error in requesting VIN: $e");
      return false;
    }
    return true;
  }

  Future<void> _startRequestingMileage() async {
    if (_vehicleVin == null) {
      CustomLogger.w("VIN is null, can't request mileage");
      return;
    }
    _mileageSendCommandTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      CustomLogger.d("Calling _mileageSendCommandTimer");
      try {
        if (_device.isDisconnected) {
          CustomLogger.w("Device is not connected, can't request mileage");
          _mileageSendCommandTimer?.cancel();
          _mileageSendCommandTimer = null;
          return;
        }
        await sendCommand(VehicleUtils.getVehicleMileageCommand(_vehicleVin!));
      } catch (e) {
        CustomLogger.e("Error in sending mileage command: $e");
      }
    });
  }

  // is called by handleResponseToVoltCommand
  Future<void> _startTelemetryCollection() async {
    if (isTripInProgress) {
      CustomLogger.w("Trip already running, skipping telemetry collection");
      return;
    }
    CustomLogger.i("Starting telemetry collection");
    await _startTrip();
    final isVinSet = await _requestVin();
    if (isVinSet) {
      // VIN is a required field for requesting mileage (see vehicle_utils.dart)
      CustomLogger.d("VIN is set, starting mileage request");
      await _startRequestingMileage();
    } else {
      await endTrip();
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
}
