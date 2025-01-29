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
import 'package:geolocator/geolocator.dart';

class IosElm327Controller {
  final BluetoothDevice _device;
  get deviceId => _device.remoteId;
  final BluetoothCharacteristic _writeCharacteristic;
  // ignore: unused_field
  final BluetoothCharacteristic _notifyCharacteristic;
  bool _isInitialized = false;
  // just a getter for task handler and to simplify the code
  bool get isTripInProgress => TripController().currentTrip != null;
  // telemetry-related:
  int? _vehicleMileage; // used for saving and tracking the mileage
  double?
      _voltageVal; // used for checking voltage of the vehicle (engine runnning)
  TripLocation? _tempLocation;
  final String vinCommand =
      "0902"; // standardized obd2 command for requesting the vin
  final String voltageCommand =
      "ATRV"; // ELM327 system command for checking vehicle voltage
  Timer? _voltageTimer; // timer to read the voltage of the vehicle
  Timer? _tripTimeoutTimer; // used for ending the trip if no data is received
  Timer?
      _mileageSendCommandTimer; // used for sending mileage requests continuously
  String _responseBuffer = ''; // buffer for incoming data from the elm327
  StreamSubscription<Position>? _positionStream;
  Vehicle? _vehicle;

  IosElm327Controller({
    required BluetoothDevice device,
    required BluetoothCharacteristic writeCharacteristic,
    required BluetoothCharacteristic notifyCharacteristic,
  })  : _device = device,
        _notifyCharacteristic = notifyCharacteristic,
        _writeCharacteristic = writeCharacteristic;

  Future<bool> initialize() async {
    _responseBuffer = '';
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
        // "ATSP0", // Set Protocol to Automatic
        //"ATE0", // Echo Off
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
    _vehicle = null;
    _vehicleMileage = null;
    _voltageVal = null;
    _tempLocation = null;
    _responseBuffer = '';
    _voltageTimer?.cancel();
    _tripTimeoutTimer?.cancel();
    _tripTimeoutTimer = null;
    _mileageSendCommandTimer?.cancel();
    _mileageSendCommandTimer = null;
    _positionStream?.cancel();
    _positionStream = null;
    CustomLogger.i("ELM327 disposed");
  }

  void _startPositionStream() {
    int vinCount = 0;
    int mileageCount = 0;
    _positionStream ??= Geolocator.getPositionStream(
            locationSettings: GpsService().locationSettings)
        .listen((Position position) async {
      if (!isTripInProgress) {
        _startTrip();
      } else {
        // trip not in progress
        if (vinCount < 10 && _vehicle == null) {
          await sendCommand(vinCommand);
          vinCount++;
        } else if (_vehicleMileage == null &&
            _vehicle != null &&
            mileageCount < 10) {
          await sendCommand(
              VehicleUtils.getVehicleMileageCommand(_vehicle!.vin));
        } else if (mileageCount >= 10) {
          CustomLogger.w("Mileage not received after 10 tries, ending trip");
          await endTrip();
        } else if (vinCount >= 10) {
          CustomLogger.w("VIN not received after 10 tries, ending trip");
          await endTrip();
        }
      }
    });
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
    if (!isTripInProgress) {
      // get location
      try {
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
          TripController().startTrip(startLocation: _tempLocation);

          // CustomLogger.d("Last known position: $lastKnownPosition");
        }
      } catch (e) {
        CustomLogger.e(
            "Error in getting location, starting trip without it: $e");
        TripController().startTrip();
      }
      // CustomLogger.d("Location found: $_tempLocation");
      // finally start a trip
      if (_tempLocation != null) {
      } else {}

      if (TripController().currentTrip != null) {
        // if a trip is started, log it
        // CustomLogger.i(_tripController!.currentTrip!.toJson());
        CustomLogger.i("Trip started");
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
        if (_vehicleMileage == null) {
          TripController()
              .endTrip(endLocation: _tempLocation, mileage: _vehicleMileage);
        } else {
          TripController().endTrip(endLocation: _tempLocation);
        }
      }
    } catch (e) {
      if (_vehicleMileage == null) {
        TripController().endTrip(mileage: _vehicleMileage);
      } else {
        TripController().endTrip();
      }
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

    // ATRV: check voltage
    if (cleanedResponse.contains("ATRV")) {
      cleanedResponse = cleanedResponse.replaceFirst("ATRV", "");
      await _handleResponseToVoltCommand(cleanedResponse);
    }
    // 0902: VIN command
    if (cleanedResponse.contains(vinCommand)) {
      cleanedResponse = cleanedResponse.replaceFirst(vinCommand, "");
      _handleResponseToVinCommand(cleanedResponse);
    }

    // mileage command
    if (cleanedResponse
        .contains(VehicleUtils.getVehicleMileageCommand(_vehicle!.vin))) {
      cleanedResponse = cleanedResponse.replaceFirst(
          VehicleUtils.getVehicleMileageCommand(_vehicle!.vin), "");
      await _handleResponseToMileageCommand(cleanedResponse);
    }
  }

  Future<void> _handleResponseToVoltCommand(String response) async {
    CustomLogger.d("Voltage response: $response");
    CustomLogger.d("Voltage command response");
    while (response.startsWith("ATRV")) {
      response = response.substring("ATRV".length).trim();
    }
    final parts = response.split("V");

    if (parts.isNotEmpty) {
      final voltageString = parts.first;
      final voltageIntValue = int.tryParse(voltageString);
      if (voltageIntValue != null) {
        _voltageVal = voltageIntValue / 10;
        CustomLogger.d("Voltage is: $_voltageVal");
        final rssi = await _device.readRssi();
        if (_voltageVal! >= 11.0 && rssi >= -70) {
          CustomLogger.i(
              "Voltage is at or above 13V, engine is running, and signal strength is good");
          CustomLogger.d("Cancelling voltage timer and starting telemetry");
          _voltageTimer?.cancel();
          _voltageTimer = null;
          _startPositionStream();
        }
      } else {
        CustomLogger.w("Voltage int couldn't be parsed, is null");
      }
    }
  }

  void _handleResponseToVinCommand(String response) {
    if (_vehicle != null) {
      CustomLogger.w("VIN already set, skipping VIN response handle");
      return;
    }
    final vin = VehicleUtils.getVehicleVin(response);
    CustomLogger.d("Calculated VIN: $vin");
    final isVinValid = _checkVin(vin);
    if (isVinValid) {
      _vehicle ??= Vehicle.fromVin(vin);
      CustomLogger.d("VIN valid and vehicle set");
    } else {
      CustomLogger.w("VIN is invalid");
    }
  }

  Future<void> _handleResponseToMileageCommand(String response) async {
    if (_vehicle == null) {
      CustomLogger.w("Vehicle is null, can't handle mileage response");
      return;
    }
    CustomLogger.d("Handling mileage response");
    final mileage = VehicleUtils.getVehicleKm(_vehicle!.vin, response);
    CustomLogger.i("Mileage response: $mileage");
    final isMileageValid = _checkMileage(mileage);

    if (isMileageValid) {
      if (isTripInProgress &&
          TripController().currentTrip?.startMileage == null) {
        TripController().updateTripStartMileage(mileage);
      }
      _tripTimeoutTimer?.cancel();
      _tripTimeoutTimer = null;
      CustomLogger.d("Trip timeout timer cancelled");
      _vehicleMileage = mileage;
      CustomLogger.d("Trip timeout timer called");
      _tripTimeoutTimer = Timer(const Duration(seconds: 10), () async {
        CustomLogger.d("Trip timeout has lapsed");
        _mileageSendCommandTimer?.cancel();
        _mileageSendCommandTimer = null;
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

  // request VIN from the vehicle

  // Future<void> _requestVin() async {
  //   const maxTries = 10; // Define this somewhere
  //   CustomLogger.d("Requesting VIN");

  //   void tryRequest(int attempt) {
  //     // Exit condition: Max attempts or VIN received
  //     if (attempt >= maxTries || _vehicleVin != null) return;

  //     // Send VIN command
  //     sendCommand(vinCommand).then((_) {
  //       CustomLogger.d("VIN command sent, attempt nr.: $attempt");
  //       // Schedule next attempt recursively after 2 seconds
  //       Timer(const Duration(seconds: 2), () => tryRequest(attempt + 1));
  //     });
  //   }

  //   // Start the first attempt
  //   tryRequest(0);
  // }
  // Future<bool> _requestVin() async {
  //   CustomLogger.d("Requesting VIN");
  //   if (_voltageVal == null) {
  //     CustomLogger.fatal("Voltage is null, can't request VIN");
  //     return false;
  //   }
  //   const int maxTries = 10;
  //   try {
  //     if (_device.isDisconnected) {
  //       CustomLogger.w("Device is not connected, can't request VIN");
  //       return false;
  //     }

  //     CustomLogger.d("Sending VIN request");
  //     for (int i = 0; i < maxTries; i++) {
  //       final success = await sendCommand(vinCommand);
  //       if (!success) {
  //         CustomLogger.w("Failed to send VIN command");
  //       } else {
  //         CustomLogger.d("VIN command sent");
  //       }

  //       await Future.delayed(
  //           const Duration(seconds: 2)); // small delay between requests
  //       if (_vehicleVin != null) {
  //         // checking if VIN was set
  //         CustomLogger.i("VIN set after $i tries");
  //         break;
  //       }
  //     }

  //     if (_vehicleVin == null) {
  //       CustomLogger.fatal("VIN not set after $maxTries tries");
  //       return false;
  //     } else {
  //       CustomLogger.d("VIN: $_vehicleVin");
  //     }
  //   } catch (e) {
  //     CustomLogger.fatal("Error in requesting VIN: $e");
  //     return false;
  //   }
  //   return true;
  // }

  // Future<void> _startRequestingMileage() async {
  //   if (_vehicleVin == null) {
  //     CustomLogger.w("VIN is null, can't request mileage");
  //     return;
  //   }
  //   _mileageSendCommandTimer =
  //       Timer.periodic(const Duration(seconds: 3), (_) async {
  //     CustomLogger.d("Calling _mileageSendCommandTimer");
  //     try {
  //       if (_device.isDisconnected) {
  //         CustomLogger.w("Device is not connected, can't request mileage");
  //         _mileageSendCommandTimer?.cancel();
  //         _mileageSendCommandTimer = null;
  //         return;
  //       }
  //       await sendCommand(VehicleUtils.getVehicleMileageCommand(_vehicleVin!));
  //     } catch (e) {
  //       CustomLogger.e("Error in sending mileage command: $e");
  //     }
  //   });
  // }

  // // is called by handleResponseToVoltCommand
  // Future<void> _startTelemetryCollection() async {
  //   if (isTripInProgress) {
  //     CustomLogger.w("Trip already running, skipping telemetry collection");
  //     return;
  //   }
  //   CustomLogger.i("Starting telemetry collection");
  //   await _startTrip();
  // await _requestVin();
  // if (_vehicleVin != null) {
  //   // VIN is a required field for requesting mileage (see vehicle_utils.dart)
  //   TripController().updateTripVehicle(Vehicle.fromVin(_vehicleVin!));
  //   CustomLogger.d("VIN is set, starting mileage request");
  //   await _startRequestingMileage();
  // } else {
  //   await endTrip();
  // }
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
