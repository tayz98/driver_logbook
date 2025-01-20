import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:async';
import 'package:driver_logbook/models/globals.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CustomBluetoothService {
  // Subscriptions
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  // Bluetooth

  List<ScanResult> _scanResults = [];
  final Guid _targetService = Guid(dotenv.get('targetService'));
  final String _targetAdvName = dotenv.get('targetAdvName');

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
