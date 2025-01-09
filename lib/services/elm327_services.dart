library telemetry_services;

import 'dart:convert';
import 'dart:async';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/services/custom_bluetooth_service.dart';
import 'package:elogbook/utils/vehicle_utils.dart';
import '../models/vehicle_diagnostics.dart';

class Elm327Service {
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  Stream<String> get elm327LogStream => _logStreamController.stream;

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
  String? vehicleVin;
  int? vehicleMileage;
  Timer? checkOBDWithVehicleMileageTimer;
  Timer? telemetryTimer;
  Timer? noResponseTimer;
  String _responseBuffer = '';
  final CustomBluetoothService customService;

  // final BluetoothDevice _device;
  // BluetoothCharacteristic writeCharacteristic;
  // BluetoothCharacteristic notifyCharacteristic;
  VehicleDiagnostics? _currentVehicleDiagnostics;

  Elm327Service(this.customService) {
    _initialize();
  }

// setup elm327 with init commands, check obd-system by sending mileage messages

  Future<void> _initialize() async {
    List<String> initCommands = [
      "ATZ", // Reset ELM327
      "ATE0", // Echo Off
      "ATL0", // Linefeeds Offr
      "ATS0", // Spaces Off
      "ATH1",
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];
    await Future.delayed(const Duration(seconds: 1));
    for (String cmd in initCommands) {
      await _sendCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 2500));
    }
    _startIgnitionStreamSubscription();
    checkOBDWithVehicleMileageTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) {
      _sendCommand(
          "2210E01"); // check vehicle mileage as indicator for obd system
    });
  }

  /// Send the command to the ELM327 device
  Future<void> _sendCommand(String command) async {
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    await customService.writeCharacteristic!
        .write(bytes, withoutResponse: true);
    _logStreamController.add("Sent command: $command");
  }

  // hier async überlegene:
  Future<bool> _checkData() async {
    await _sendCommand("0902");
    await Future.delayed(const Duration(milliseconds: 1000));
    bool vin = await _checkVin();
    return dataIsValid = vin && _checkMileage();
  }

  void handleReceivedData(List<int> data) {
    String incomingData = utf8.decode(data);
    _responseBuffer += incomingData;
    int endIndex = _responseBuffer.indexOf(">");
    while (endIndex != -1) {
      String completeResponse = _responseBuffer.substring(0, endIndex).trim();
      _responseBuffer = _responseBuffer.substring(endIndex + 1);
      _processCompleteResponse(completeResponse);
      //_logStreamController.add("Buffer: $completeResponse");
      endIndex = _responseBuffer.indexOf(">");
    }
  }

  void _processCompleteResponse(String response) {
    String cleanedResponse = response
        .trim()
        .replaceAll("]", "")
        .replaceAll("[", "")
        .replaceAll(">", "")
        .replaceAll("<", "")
        .replaceAll(":", "")
        .replaceAll(".", "")
        .replaceAll(" ", "")
        .replaceAll("\u00A0", "")
        .replaceAll(RegExp(r"\s+"), "")
        .replaceAll("SEARCHING", "")
        .replaceAll("STOPPED", "")
        .replaceAll("ELM327V15", "")
        .replaceAll("NODATA", "")
        .replaceAll("TIMEOUT", "")
        .replaceAll("CANERROR", "")
        .replaceAll("OK", "");

    if (cleanedResponse.isEmpty) return; // unsolicited response, ignore it
    _logStreamController.add("Received: $cleanedResponse");
    if (cleanedResponse.contains("6210")) {
      _handleResponseToMileageCommand(cleanedResponse);
    }

    // 7E8 is the device id, 10 is the FF,
    //14 is the length of the response (20 bytes),
    //49 is the answer to the mode 09
    if (cleanedResponse.contains("7E8101449")) {
      _handleResponseToVINCommand(cleanedResponse);
    }
  }

  Future<bool> _checkVin() async {
    if (vehicleVin == null) {
      _logStreamController.add("Checking VIN: $vehicleVin");
      for (int i = 0; i < 3; i++) {
        await _sendCommand("0902");
        await Future.delayed(const Duration(milliseconds: 1000));
        if (vehicleVin != null) {
          break;
        }
      }
    }

    if (vehicleVin != null && vehicleVin!.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      if (vinRegex.hasMatch(vehicleVin!)) {
        _logStreamController.add("VIN is valid");
        return true;
      }
    }
    _logStreamController.add("VIN is invalid");
    return false;
  }

  bool _checkMileage() {
    _logStreamController.add("Checking Mileage: $vehicleMileage");
    if (vehicleMileage != null &&
        vehicleMileage! >= 0 &&
        vehicleMileage! <= 2000000) {
      _logStreamController.add("Mileage is valid");
      return true;
    }
    _logStreamController.add("Mileage is invalid");
    return false;
  }

  void _startIgnitionStreamSubscription() {
    _logStreamController.add("Starting ignition stream subscription");
    _ignitionStreamController.stream.listen((isIgnitionTurnedOn) async {
      if (isIgnitionTurnedOn) {
        _logStreamController.add("Ignition turned ON");
        // Cancel any pending OFF timer
        // Validate data and start trip monitoring
        bool dataIsValid = await _checkData();
        if (dataIsValid) {
          _logStreamController.add("Data is valid. Starting trip monitoring.");
          _startTelemetryCollection();
        } else {
          showBasicNotification(
              title: "Data is invalid", body: "Ending trip monitoring");
          checkOBDWithVehicleMileageTimer?.cancel();
          _logStreamController.add("Data is invalid. Ending trip monitoring.");
          // TODO: Notify user of invalid data, he can turn the ignition off and on again
          showBasicNotification(title: "Trip Ending", body: "Data incorrect");
          // handle invalid data (e.g. retry)
        }
      } else if (!isIgnitionTurnedOn) {
        _logStreamController.add("Ignition turned OFF");
        // Set a timer to delay trip monitoring termination
        _endTelemetryCollection();
      } else {
        _logStreamController.add("Ignition state unchanged.");
      }
    });
  }

  void _startTelemetryCollection() {
    // check if car mileage has changed in the last 10 seconds with a timer:
    if (!isTelemetryRunning) {
      isTelemetryRunning = true;
    }
    showBasicNotification(
        title: "Telemetry", body: "Telemetry collection is running");
    _logStreamController.add("Telemetry collection started");

    // Start a periodic timer to collect telemetry data every X seconds
    //_telemetryStartedController.add(null);
  }

  void dispose() {
    _logStreamController.close();
    _tripDataStreamController.close();
    _ignitionStreamController.close();
    _vehicleDiagnosticsStreamController.close();
    _telemetryStartedController.close();
    checkOBDWithVehicleMileageTimer?.cancel();
    telemetryTimer?.cancel();
    noResponseTimer?.cancel();
    // Add any additional disposal logic here
  }

  _endTelemetryCollection() {
    showBasicNotification(
        title: "Telemetry", body: "Telemetry collection ended");
    _logStreamController.add("Trip monitoring ended. Saving trip data.");
    _saveTripData();
    dispose();
  }

  void _saveTripData() {
    _logStreamController
        .add("Saving trip data: VIN: $vehicleVin Mileage: $vehicleMileage");
  }

  void _handleResponseToVINCommand(String response) {
    vehicleVin = VehicleUtils.getVehicleVin(response);
    if (vehicleVin != null && vehicleMileage != null) {
      _currentVehicleDiagnostics = VehicleDiagnostics(
        vin: vehicleVin!,
        currentMileage: vehicleMileage!,
      );
    }
    _logStreamController.add("VIN received: $vehicleVin");
  }

  void _handleResponseToMileageCommand(String response) {
    noResponseTimer?.cancel();
    noResponseTimer = Timer(const Duration(seconds: 10), () {
      // This code runs if no response is received for 10 seconds
      if (isIgnitionTurnedOn) {
        _logStreamController
            .add("No response to mileage command. Ignition turned OFF.");
        _updateIgnitionState(
            false); // Unified function to handle ignition state
      }
    });
    vehicleMileage = VehicleUtils.getVehicleKm(response);
    if (!isIgnitionTurnedOn) {
      _updateIgnitionState(true); // Unified function to handle ignition state
    }

    _logStreamController.add("Mileage received: $vehicleMileage");
    if (vehicleMileage != null &&
        vehicleVin != null &&
        _currentVehicleDiagnostics != null) {
      _currentVehicleDiagnostics!.copyWith(vin: vehicleVin);
    }
  }

  bool isUpdatingIgnitionState = false;

  void _updateIgnitionState(bool newState) {
    if (isIgnitionTurnedOn != newState) {
      isUpdatingIgnitionState = true;
      isIgnitionTurnedOn = newState;
      _ignitionStreamController.add(newState);
      _logStreamController.add("Ignition state updated: $newState");
      isUpdatingIgnitionState = false;
    }
  }
}
