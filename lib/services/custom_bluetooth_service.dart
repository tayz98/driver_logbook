library telmetry_services;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'package:elogbook/models/globals.dart';

class CustomBluetoothService {
  // Streams
  // final StreamController<String> _logStreamController =
  //     StreamController<String>.broadcast();
  // Stream<String> get logStream => _logStreamController.stream;

  // Stream<String> get telemetryLogStream =>
  //     elm327Service?.elm327LogStream ?? const Stream.empty();

  // Subscriptions
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  // Bluetooth

  List<ScanResult> _scanResults = [];
  final Guid _targetService = Guid("0000fff0-0000-1000-8000-00805f9b34fb");
  final String _targetAdvName = "VEEPEAK";

  CustomBluetoothService() {
    _initialize();
  }

  Future<void> _initialize() async {
    _scanResultsSubscription ??= FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results;
    });
  }

  void dispose() {
    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
  }

  // Future<void> _saveDeviceIds(List<String> deviceIds) async {
  //   for (var id in deviceIds) {
  //     if (!_knownRemoteIds.contains(id)) {
  //       _knownRemoteIds.add(id);
  //     }
  //   }
  //   //await prefs.setStringList('knownRemoteIds', _knownRemoteIds);
  //   FlutterForegroundTask.sendDataToTask(_knownRemoteIds);
  // }

  Future<void> scanForDevices() async {
    try {
      await FlutterBluePlus.startScan(
          withServices: [_targetService],
          withNames: [_targetAdvName],
          timeout: const Duration(seconds: 5));
      await Future.delayed(const Duration(milliseconds: 5100));
      final deviceIds = _scanResults.map((r) => r.device.remoteId.str).toList();
      foundDeviceIds = deviceIds;
      print("Found devices: $foundDeviceIds");
      FlutterForegroundTask.sendDataToTask(foundDeviceIds);
    } catch (e) {
      debugPrint("Error scanning for devices: $e");
      return;
    }
  }
}
