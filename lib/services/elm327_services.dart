import 'dart:convert';
import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/car_utils.dart';
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
  String? carVin;
  double? carMileage;
  Timer? ignitionOffTimer;
  Timer? checkIgnitionTimer;
  Timer? telemetryTimer;
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

    bool previousState = isIgnitionTurnedOn;

    if (response.contains("ON")) {
      isIgnitionTurnedOn = true;
      _ignitionStreamController.add(true);
      _logStreamController.add("Ignition turned ON");
    } else if (response.contains("OFF")) {
      isIgnitionTurnedOn = false;
      _logStreamController.add("Ignition turned OFF");
    }

    if (isIgnitionTurnedOn != previousState) {
      _ignitionStreamController.add(isIgnitionTurnedOn);
    }

    // Handle VIN once
    if (response.startsWith("0902")) {
      carVin = CarUtils.getCarVin(response);
      _logStreamController.add("VIN received: $carVin");
      if (_currentVehicleDiagnostics == null && carVin != null) {
        _currentVehicleDiagnostics = VehicleDiagnostics(
          vin: carVin!,
          currentMileage: carMileage ?? 0.0,
        );
        _vehicleDiagnosticsStreamController.add(_currentVehicleDiagnostics!);
        _logStreamController.add("VIN set: $_currentVehicleDiagnostics.vin");
      } else {
        _logStreamController.add("VIN already set. Ignoring.");
      }
    }

    if (response.contains("10E1")) {
      carMileage = CarUtils.getCarKm(response);
      _logStreamController.add("Mileage received: $carMileage");
      if (_currentVehicleDiagnostics != null && carMileage != null) {
        _currentVehicleDiagnostics = _currentVehicleDiagnostics!.copyWith(
          currentMileage: carMileage!,
        );
        _vehicleDiagnosticsStreamController.add(_currentVehicleDiagnostics!);
        _logStreamController.add(
            "Mileage updated: ${_currentVehicleDiagnostics!.currentMileage}");
      } else {
        _logStreamController.add("Mileage received before VIN. Ignoring.");
      }
    }
  }

  Future<bool> _checkData() async {
    await _sendCommand("0902");
    await Future.delayed(const Duration(milliseconds: 500));
    await _sendCommand("2210E01");
    await Future.delayed(const Duration(milliseconds: 500));
    return dataIsValid = _checkVin() && _checkMileage();
  }

  bool _checkVin() {
    if (carVin != null && carVin!.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      return vinRegex.hasMatch(carVin!);
    }
    return false;
  }

  bool _checkMileage() {
    if (carMileage != null && carMileage! >= 0 && carMileage! <= 2000000) {
      return true;
    }
    return false;
  }

  void _startIgnitionStreamSubscription() {
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
  }

  void _endTelemetryCollection() {
    showBasicNotification(
        title: "Telemetry", body: "Telemetry collection ended");
    _logStreamController.add("Trip monitoring ended. Saving trip data.");
    checkIgnitionTimer?.cancel();
    telemetryTimer?.cancel();
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
