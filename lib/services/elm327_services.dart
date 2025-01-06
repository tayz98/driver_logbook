import 'dart:convert';
import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/car_utils.dart';

// TODO: use provider, bloc or riverpod for state managing the vehicle data
class Elm327Service {
  final BluetoothDevice device;
  BluetoothCharacteristic writeCharacteristic;
  BluetoothCharacteristic notifyCharacteristic;
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logStreamController.stream;
  final StreamController<bool> ignitionStreamController =
      StreamController<bool>.broadcast();
  bool ignitionIsTurnedOn = false;
  bool dataIsValid = false;
  String? carVin;
  double? carMileage;
  Timer? ignitionOffTimer;
  Timer? checkIgnitionTimer;
  late Future<bool> _dataCheckFuture;

  Elm327Service(
      this.device, this.writeCharacteristic, this.notifyCharacteristic) {
    _initialize();
  }

  Future<void> _initialize() async {
    List<String> initCommands = [
      "ATZ", // Reset ELM327
      "ATE0", // Echo Off
      "ATL0", // Linefeeds Off
      "ATS0", // Spaces Off
      "ATH0", // Headers Off
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];
    await Future.delayed(const Duration(seconds: 1));
    for (String cmd in initCommands) {
      await _sendCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _logStreamController.add("ELM327 Initialized");
    _dataCheckFuture = _checkData();
    // repeat ignition status check every 4 seconds
    checkIgnitionTimer =
        Timer.periodic(const Duration(seconds: 4), (timer) async {
      await _sendCommand("AT IGN");
    });
    _startIgnitionStreamSubscription();
  }

  Future<void> _sendCommand(String command) async {
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await writeCharacteristic.write(bytes, withoutResponse: true);
      _logStreamController.add("Sent: $command");
    } catch (e) {
      _logStreamController.add("Error sending command '$command': $e");
      if (command == "ATZ") {
        _logStreamController.add("Failed to reset ELM327. Disconnecting.");
        //device.disconnect();
        // or other logic here for critical commands
      } else {
        return Future.error(e);
      }
    }
  }

  void handleReceivedData(List<int> data) {
    String response = utf8.decode(data).trim().replaceAll(" ", "");
    _logStreamController.add("Received: $response");

    bool previousState = ignitionIsTurnedOn;

    if (response.contains("ON")) {
      ignitionStreamController.add(true);
      _logStreamController.add("Ignition turned ON");
    } else if (response.contains("OFF")) {
      ignitionIsTurnedOn = false;
      _logStreamController.add("Ignition turned OFF");
    }

    if (ignitionIsTurnedOn != previousState) {
      ignitionStreamController.add(ignitionIsTurnedOn);
    }

    if (response.startsWith("0902")) {
      carVin = CarUtils.getCarVin(response);
      _logStreamController.add("VIN: $carVin");
    }

    if (response.contains("10E1")) {
      carMileage = CarUtils.getCarKm(response);
      _logStreamController.add("Mileage: $carMileage");
    }
  }

  Future<bool> _checkData() async {
    await _sendCommand("0902");
    await Future.delayed(const Duration(milliseconds: 500));
    await _sendCommand("2210E01");
    await Future.delayed(const Duration(milliseconds: 500));
    return dataIsValid = await _checkVin() && await _checkMileage();
  }

  Future<bool> _checkVin() async {
    // Ensure carVin is not null
    if (carVin != null) {
      // Check length
      if (carVin!.length == 17) {
        // Regex to validate VIN format (excludes I, O, Q)
        final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
        if (vinRegex.hasMatch(carVin!)) {
          return Future.value(true);
        }
      }
    }
    return Future.value(false);
  }

  Future<bool> _checkMileage() async {
    // Ensure mileage is not null
    if (carMileage != null) {
      // Check if mileage is within a realistic range
      if (carMileage! >= 0 && carMileage! <= 2000000) {
        return Future.value(true); // Valid mileage
      }
    }
    return Future.value(false); // Invalid mileage
  }

  void _startIgnitionStreamSubscription() {
    ignitionStreamController.stream.listen((isIgnitionOn) async {
      if (isIgnitionOn == true) {
        _logStreamController.add("Ignition turned ON");
        // Cancel any pending OFF timer
        ignitionOffTimer?.cancel();
        // Validate data and start trip monitoring
        bool dataIsValid = await _dataCheckFuture;
        if (dataIsValid) {
          _logStreamController.add("Data is valid. Starting trip monitoring.");
          _startTelemetryCollection();
        } else {
          showBasicNotification(
              title: "Data is invalid", body: "Ending trip monitoring");
          checkIgnitionTimer?.cancel();
          _logStreamController.add("Data is invalid. Ending trip monitoring.");
          // TODO: Notify user of invalid data, he can turn the ignition off and on again
          showBasicNotification(title: "Trip Ending", body: "Data incorrect");
          // handle invalid data (e.g. retry)
        }
      } else {
        _logStreamController.add("Ignition turned OFF");
        // Set a timer to delay trip monitoring termination
        ignitionOffTimer = Timer(const Duration(seconds: 10), () {
          _logStreamController.add(
              "Ignition OFF confirmed after delay. Ending trip monitoring.");
          _endTelemetryCollection();
        });
      }
    });
  }

  void _startTelemetryCollection() async {
    showBasicNotification(
        title: "Telemetry", body: "Telemetry collection is running");
    _logStreamController.add("Telemetry collection started");
    await _sendCommand("2210E01"); // mileage
    _logStreamController
        .add("Telemetry data collected: VIN: $carVin, Mileage: $carMileage");
  }

  void _endTelemetryCollection() {
    showBasicNotification(
        title: "Telemetry", body: "Telemetry collection ended");
    _logStreamController.add("Trip monitoring ended. Saving trip data.");
    _saveTripData();
  }

  void _saveTripData() {
    _logStreamController
        .add("Saving trip data: VIN: $carVin Mileage: $carMileage");
  }

  void dispose() {
    _logStreamController.close();
    ignitionStreamController.close();
    ignitionOffTimer?.cancel();
    checkIgnitionTimer?.cancel();
  }
}
