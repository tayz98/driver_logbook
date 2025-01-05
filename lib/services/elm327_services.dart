import 'dart:convert';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/car_utils.dart';

class Elm327Service {
  final BluetoothDevice device;
  BluetoothCharacteristic? writeCharacteristic;
  BluetoothCharacteristic? notifyCharacteristic;
  final StreamController<List<String>> logStream =
      StreamController<List<String>>.broadcast();
  final StreamController<bool> ignitionStreamController =
      StreamController<bool>.broadcast();
  bool ignitionIsTurnedOn = false;
  bool dataIsValid = false;
  String? carVin;
  double? carMileage;
  Timer? ignitionOffTimer;

  Elm327Service(this.device);

  Future<void> initialize() async {
    List<String> initCommands = [
      "ATZ", // Reset ELM327
      "ATE0", // Echo Off
      "ATL0", // Linefeeds Off
      "ATS0", // Spaces Off
      "ATH0", // Headers Off
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];

    for (String cmd in initCommands) {
      await sendCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    logStream.add(["ELM327 Initialized"]);
  }

  Future<void> sendCommand(String command) async {
    if (writeCharacteristic == null) {
      logStream.add(["Write Characteristic is null"]);
      return;
    }
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await writeCharacteristic!.write(bytes, withoutResponse: true);
      logStream.add(["Sent: $command"]);
    } catch (e) {
      logStream.add(["Error sending command '$command': $e"]);
    }
  }

  void handleReceivedData(List<int> data) {
    String response = utf8.decode(data).trim().replaceAll(" ", "");
    logStream.add(["Received: $response"]);

    bool previousState = ignitionIsTurnedOn;

    if (response.contains("ON")) {
      ignitionIsTurnedOn = true;
    } else if (response.contains("OFF")) {
      ignitionIsTurnedOn = false;
    }

    if (ignitionIsTurnedOn != previousState) {
      ignitionStreamController.add(ignitionIsTurnedOn);
    }

    if (response.startsWith("0902")) {
      carVin = CarUtils.getCarVin(response);
    }

    if (response.contains("10E1")) {
      carMileage = CarUtils.getCarKm(response);
    }
  }

  Future<void> checkData() async {
    dataIsValid = await checkVin() && await checkMileage();
  }

  Future<bool> checkVin() async {
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

  Future<bool> checkMileage() async {
    // Ensure mileage is not null
    if (carMileage != null) {
      // Check if mileage is within a realistic range
      if (carMileage! >= 0 && carMileage! <= 2000000) {
        return Future.value(true); // Valid mileage
      }
    }
    return Future.value(false); // Invalid mileage
  }

  void startIgnitionStreamSubscription() {
    ignitionStreamController.stream.listen((isIgnitionOn) async {
      if (isIgnitionOn) {
        logStream.add(["Ignition turned ON"]);

        // Cancel any pending OFF timer
        ignitionOffTimer?.cancel();

        // Validate data and start trip monitoring
        await checkData();
        if (dataIsValid) {
          logStream.add(["Data is valid. Starting trip monitoring."]);
          startTelemetryCollection();
        } else {
          logStream.add(["Data is invalid. Cannot start trip monitoring."]);
        }
      } else {
        logStream.add(["Ignition turned OFF"]);

        // Set a timer to delay trip monitoring termination
        ignitionOffTimer = Timer(const Duration(seconds: 10), () {
          logStream.add(
              ["Ignition OFF confirmed after delay. Ending trip monitoring."]);
          endTelemetryCollection();
        });
      }
    });
  }

  void startTelemetryCollection() async {
    logStream.add(["Telemetry collection started"]);

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!ignitionIsTurnedOn) {
        timer.cancel();
        logStream.add(["Telemetry collection stopped"]);
        return;
      }

      await sendCommand("AT IGN"); // ignition status
      await Future.delayed(const Duration(milliseconds: 500));
      await sendCommand("2210E01"); // mileage
      logStream.add(
          ["Telemetry data collected: VIN: $carVin, Mileage: $carMileage"]);
    });
  }

  void endTelemetryCollection() {
    logStream.add(["Trip monitoring ended. Saving trip data."]);
    saveTripData();
  }

  void saveTripData() {
    logStream
        .add(["Saving trip data:", "VIN: $carVin", "Mileage: $carMileage"]);
  }

  void dispose() {
    logStream.close();
    ignitionStreamController.close();
    ignitionOffTimer?.cancel();
  }
}
