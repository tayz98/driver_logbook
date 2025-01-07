import 'dart:convert';
import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/utils/vehicle_utils.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/vehicle_diagnostics.dart';

class Elm327Service {
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logStreamController.stream;

  final StreamController<String> _tripDataStreamController =
      StreamController<String>.broadcast();
  Stream<String> get tripDataStream => _tripDataStreamController.stream;

  final StreamController<bool> _ignitionStreamController =
      StreamController<bool>.broadcast();
  Stream<bool> get ignitionStream => _ignitionStreamController.stream;

  final StreamController<VehicleDiagnostics>
      _vehicleDiagnosticsStreamController =
      StreamController<VehicleDiagnostics>.broadcast();
  Stream<VehicleDiagnostics> get vehicleStream =>
      _vehicleDiagnosticsStreamController.stream;

  final StreamController<void> _telemetryStartedController =
      StreamController<void>.broadcast();
  Stream<void> get telemetryStartedStream => _telemetryStartedController.stream;

  bool isIgnitionTurnedOn = false;
  bool dataIsValid = false;
  bool isTelemetryRunning = false;
  String? carVin;
  double? carMileage;
  Timer? ignitionOffTimer;
  Timer? checkIgnitionTimer;
  Timer? telemetryTimer;
  String? _currentCommand;
  bool _isCommandInProgress = false;

  final BluetoothDevice device;
  BluetoothCharacteristic writeCharacteristic;
  BluetoothCharacteristic notifyCharacteristic;
  VehicleDiagnostics? _currentVehicleDiagnostics;

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
      "ATH0", // Headers off, so only the payload is returned
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];
    await Future.delayed(const Duration(seconds: 1));
    for (String cmd in initCommands) {
      await _sendCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    checkIgnitionTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _sendCommand("2210E01"); // malfunction indicator test
    });
    _startIgnitionStreamSubscription();
  }

  /// Send the command to the ELM327 device
  Future<void> _sendCommand(String command) async {
    while (_isCommandInProgress) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _isCommandInProgress = true;
    _currentCommand = command;
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    await writeCharacteristic.write(bytes, withoutResponse: true);
    _logStreamController.add("Sent command: $command");
  }

  Future<bool> _checkData() async {
    for (int i = 0; i < 3; i++) {
      await _sendCommand("0902");
      await Future.delayed(const Duration(milliseconds: 4000));
    }
    return dataIsValid = _checkVin() && _checkMileage();
  }

  void handleReceivedData(List<int> data) {
    String response = utf8
        .decode(data)
        .trim()
        .replaceAll("]", "")
        .replaceAll("[", "")
        .replaceAll(">", "")
        .replaceAll("<", "")
        .replaceAll(":", "")
        .replaceAll("SEARCHING", "")
        .replaceAll(".", "")
        .replaceAll("STOPPED", "")
        .replaceAll("NO DATA", "")
        .replaceAll("TIMEOUT", "")
        .replaceAll(" ", "");
    if (response.isEmpty) return;
    _logStreamController.add("Received: $response");

    if (_currentCommand == null) return;
    if (_currentCommand!.startsWith("AT")) {
      _logStreamController.add("Command with AT received");
    }

    if (_currentCommand == "0101") {
      if (response.contains("")) {
        isIgnitionTurnedOn = true;
        _ignitionStreamController.add(true);
        _logStreamController.add("Ignition turned ON");
      } else {
        isIgnitionTurnedOn = false;
        _ignitionStreamController.add(false);
      }
    }

    if (_currentCommand == "2210E01") {
      if (response.startsWith("6210")) {
        carMileage = VehicleUtils.getVehicleKm(response);
        _logStreamController.add("Mileage received: $carMileage");
        if (_currentVehicleDiagnostics != null && carMileage != null) {
          _currentVehicleDiagnostics =
              _currentVehicleDiagnostics!.copyWith(currentMileage: carMileage!);
          _vehicleDiagnosticsStreamController.add(_currentVehicleDiagnostics!);
          _logStreamController.add(
              "Mileage updated: ${_currentVehicleDiagnostics!.currentMileage}");
        } else {
          _logStreamController.add("Mileage received before VIN. Ignoring.");
        }
      }
    }

    if (_currentCommand == "0902") {
      if (response.length >= 17) {
        carVin = VehicleUtils.getCarVin(response);
        _logStreamController.add("VIN received: $carVin");
        if (_currentVehicleDiagnostics == null && carVin != null) {
          _logStreamController.add("VIN received: $carVin");
          _currentVehicleDiagnostics = VehicleDiagnostics(
            vin: carVin!,
            currentMileage: carMileage ?? 0.0,
          );
          //_vehicleDiagnosticsStreamController.add(_currentVehicleDiagnostics!);
          //_logStreamController.add("VIN set:");
        } else {
          _logStreamController.add("VIN already set. Ignoring.");
        }
      }
    }
  }

  bool _checkVin() {
    _logStreamController.add("Checking VIN: $carVin");
    if (carVin != null && carVin!.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      return vinRegex.hasMatch(carVin!);
    }
    return false;
  }

  bool _checkMileage() {
    _logStreamController.add("Checking Mileage: $carMileage");
    if (carMileage != null && carMileage! >= 0 && carMileage! <= 2000000) {
      return true;
    }
    return false;
  }

  void _startIgnitionStreamSubscription() {
    _logStreamController.add("Ignition status: $isIgnitionTurnedOn");
    _ignitionStreamController.stream.listen((isIgnitionTurnedOn) async {
      if (isIgnitionTurnedOn) {
        _logStreamController.add("Ignition turned ON");
        // Cancel any pending OFF timer
        ignitionOffTimer?.cancel();
        // Validate data and start trip monitoring
        bool dataIsValid = await _checkData();
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
    // Start a periodic timer to collect telemetry data every X seconds
    telemetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _sendCommand("2210E01"); // Request mileage
      _logStreamController
          .add("Telemetry data collected: VIN: $carVin, Mileage: $carMileage");
      // You can emit data to streams or handle it as needed
    });
    _telemetryStartedController.add(null);
    if (!isTelemetryRunning) {
      isTelemetryRunning = true;
    }
  }

  void _endTelemetryCollection() {
    showBasicNotification(
        title: "Telemetry", body: "Telemetry collection ended");
    _logStreamController.add("Trip monitoring ended. Saving trip data.");
    checkIgnitionTimer?.cancel();
    telemetryTimer?.cancel();
    isTelemetryRunning = false;
    _saveTripData();
  }

  void _saveTripData() {
    _logStreamController
        .add("Saving trip data: VIN: $carVin Mileage: $carMileage");
  }

  void dispose() {
    _logStreamController.close();
    _ignitionStreamController.close();
    _tripDataStreamController.close();
    _vehicleDiagnosticsStreamController.close();
    ignitionOffTimer?.cancel();
    checkIgnitionTimer?.cancel();
    _telemetryStartedController.close();
    ignitionOffTimer = null;
    checkIgnitionTimer = null;
    telemetryTimer?.cancel();
    telemetryTimer = null;
  }
}
