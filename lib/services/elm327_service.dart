library telemetry_services;

import 'dart:convert';
import 'dart:async';
import 'package:elogbook/models/trip_status.dart';
import 'package:elogbook/notification_configuration.dart';
import 'package:elogbook/services/custom_bluetooth_service.dart';
import 'package:elogbook/utils/vehicle_utils.dart';
import '../models/vehicle_diagnostics.dart';
import '../providers/providers.dart';
import '../providers/trip_notifier.dart';

class Elm327Service {
  // streams
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  Stream<String> get elm327LogStream => _logStreamController.stream;
  final StreamController<void> _mileageResponseController =
      StreamController<void>.broadcast();
  Stream<void> get mileageResponseStream => _mileageResponseController.stream;

  final StreamController<VehicleDiagnostics>
      _vehicleDiagnosticsStreamController =
      StreamController<VehicleDiagnostics>.broadcast();
  Stream<VehicleDiagnostics> get vehicleStream =>
      _vehicleDiagnosticsStreamController.stream;

// variables
  String? _vehicleVin;
  int? _vehicleMileage;
  int? _previousMileage;
  Timer? mileageSendCommandTimer;
  Timer? _noResponseTimer;
  String _responseBuffer = '';
  final CustomBluetoothService customService;
  final String skodaMileageCommand = "2210E01";
  final String vinCommand = "0902";

  Elm327Service(this.customService) {
    _initialize();
  }

  TripNotifier get tripNotifier {
    return customService.ref.read(tripProvider.notifier);
  }

// setup elm327 with init commands, check obd-system by sending mileage messages

  Future<void> _initialize() async {
    List<String> initCommands = [
      "ATZ", // Reset ELM327
      "ATE0", // Echo Off
      "ATL0", // Linefeeds Offr
      "ATS0", // Spaces Off
      "ATH1", // Headers On
      "ATSP0", // Set Protocol to Automatic
      "ATSH 7E0", // Set Header to 7E0
    ];
    await Future.delayed(const Duration(seconds: 1));
    for (String cmd in initCommands) {
      await _sendCommand(cmd);
      await Future.delayed(const Duration(
          milliseconds: 2500)); // wait for every command to process
    }
    // after initialization, check if the obd-system (ignition) is turned on by sending the mileage command continuously
    mileageSendCommandTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _sendCommand(skodaMileageCommand);
    });
    _startTelemetryCollection();
  }

  void _startTelemetryCollection() {
    _mileageResponseController.stream.listen((_) async {
      if (await _checkData()) {
        _updateDiagnostics();

        // use a timer to check if the obd-system (ignition) is turned off
        _noResponseTimer?.cancel();
        _noResponseTimer = Timer(const Duration(seconds: 10), () {
          _endTelemetryCollection();
        });
      } else {
        _logStreamController.add("Data is invalid. Trip cannot be recorded.");
        dispose();
      }
    });
  }

  // send command to elm327
  Future<void> _sendCommand(String command) async {
    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    await customService.writeCharacteristic!
        .write(bytes, withoutResponse: true);
    _logStreamController.add("Sent command: $command");
  }

  // check if VIN and mileage are valid
  Future<bool> _checkData() async {
    bool vin = await _checkVin();
    bool mileage =
        _checkMileageOfSkoda(); // mileage already known by now, that's why it's not awaited
    return vin && mileage;
  }

  // manage incoming data from elm327
  void handleReceivedData(List<int> data) {
    // decode it and add it to the buffer because responses can be split into multiple parts
    String incomingData = utf8.decode(data);
    _responseBuffer += incomingData;
    int endIndex = _responseBuffer.indexOf(">"); // ">" is the end of a response
    while (endIndex != -1) {
      String completeResponse = _responseBuffer.substring(0, endIndex).trim();
      _responseBuffer = _responseBuffer.substring(endIndex + 1);
      _processCompleteResponse(completeResponse);
      endIndex = _responseBuffer.indexOf(">");
    }
  }

  // process the complete response from elm327
  void _processCompleteResponse(String response) {
    // remove all unnecessary characters or words
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
        //.replaceAll("ELM327V15", "")
        .replaceAll("NODATA", "")
        .replaceAll("TIMEOUT", "")
        .replaceAll("CANERROR", "")
        .replaceAll("OK", "");

    if (cleanedResponse.isEmpty) return; // unsolicited response, ignore it
    _logStreamController.add("Received: $cleanedResponse");
    // every mileage response starts with 6210
    if (cleanedResponse.contains("6210")) {
      // startsWith doesn't work for some reason, that's why contains is used
      _handleResponseToSkodaMileageCommand(cleanedResponse);
    }

    // 7E8 is the device id, 10 is the FF,
    //14 is the length of the response (20 bytes),
    //49 is the answer to the mode 09
    if (cleanedResponse.contains("7E8101449")) {
      // startsWith doesn't work here too
      _handleResponseToVINCommand(cleanedResponse);
    }
  }

  // check if VIN is valid
  Future<bool> _checkVin() async {
    if (_vehicleVin == null) {
      _logStreamController.add("Checking VIN: $_vehicleVin");
      for (int i = 0; i < 3; i++) {
        // if VIN takes too long to receive, send the command again
        await _sendCommand(vinCommand);
        await Future.delayed(const Duration(milliseconds: 2000));
        if (_vehicleVin != null) {
          break;
        }
      }
      _logStreamController.add("VIN is invalid");
    }

    if (_vehicleVin?.length == 17) {
      final RegExp vinRegex = RegExp(r'^[A-HJ-NPR-Z0-9]+$');
      if (vinRegex.hasMatch(_vehicleVin!)) {
        _logStreamController.add("VIN is valid");
        return true;
      }
    }
    return false;
  }

  // check if mileage is valid
  bool _checkMileageOfSkoda() {
    _logStreamController.add("Checking Mileage: $_vehicleMileage");
    if (_vehicleMileage != null &&
        _vehicleMileage! >= 0 &&
        _vehicleMileage! <= 2000000) {
      _logStreamController.add("Mileage is valid");
      return true;
    }
    _logStreamController.add("Mileage is invalid");
    return false;
  }

  void dispose() {
    _logStreamController.close();
    _vehicleDiagnosticsStreamController.close();
    mileageSendCommandTimer?.cancel();
    _noResponseTimer?.cancel();
  }

  void _updateDiagnostics() {
    if (_vehicleMileage == null || _vehicleVin == null) return;

    if (tripNotifier.isTripInProgress) {
      if (_previousMileage != null && _previousMileage == _vehicleMileage) {
        return; // mileage has not changed, no need to update
      }
      tripNotifier.updateMileage(_vehicleMileage!);
    } else {
      tripNotifier.initializeTrip(
        startMileage: _vehicleMileage!,
        vin: _vehicleVin!,
      );
      showBasicNotification(title: "Trip started!", body: "Trip has started");
    }
  }

  _endTelemetryCollection() {
    _logStreamController.add("Trip ended.");
    showBasicNotification(title: "END TRIP", body: "Trip has ended");
    tripNotifier.endTrip();
    dispose();
  }

  void _handleResponseToVINCommand(String response) {
    _vehicleVin = VehicleUtils.getVehicleVin(response);
    _logStreamController.add("VIN received: $_vehicleVin");
  }

  void _handleResponseToSkodaMileageCommand(String response) {
    if (_vehicleMileage != null) {
      _previousMileage = _vehicleMileage;
    }
    _vehicleMileage = VehicleUtils.getVehicleKmOfSkoda(response);
    _mileageResponseController.add(null);
  }
}
