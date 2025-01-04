import 'dart:convert';

import 'package:elogbook/utils/extra.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/car_utils.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

// this widget is the entry point where a user can scan for devices
class _HomeState extends State<Home> {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  Guid targetService = Guid("0000fff0-0000-1000-8000-00805f9b34fb");
  Guid writeGuid = Guid("0000fff2-0000-1000-8000-00805f9b34fb");
  Guid notificator = Guid("00002902-0000-1000-8000-00805f9b34fb");
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  StreamSubscription<int>? _mtuSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  late StreamSubscription<List<ScanResult>> _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<int>? _rssiStreamSubscription;

  static const String targetMac = "8C:DE:52:DE:CB:DC";
  final int connectRsiTreshold = -100;
  final int disconnectRsiTreshold = -110;
  String carVin = "";
  int carKm = 0;
  final List<String> _log = [];
  bool _isConnecting = false;
  bool _isScanning = false;
  int? rssi;
  int? mtsuSize;
  Timer? _disconnectTimer;

  Stream<int> _rssiStream(BluetoothDevice device, Duration interval) async* {
    while (true) {
      try {
        int rssiValue = await device.readRssi();
        yield rssiValue;
      } catch (e) {
        _log.add("Error reading RSSI: $e");
        await _disconnect();
        break;
      }
      await Future.delayed(interval);
    }
  }

  @override
  void initState() {
    super.initState();
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.remoteId.toString().toUpperCase() == targetMac) {
          if (r.rssi > connectRsiTreshold &&
              _isConnecting == false &&
              _connectedDevice == null) {
            setState(() {
              _log.add("Found Device has acceptable RSSI: ${r.rssi}");
            });
            automaticConnect(r.device);
            break;
          }
        }
      }
    }, onError: (e) {
      _log.add("Scan error: $e");
    });
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
      if (_isScanning == false && _connectedDevice == null) {
        FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 5), continuousUpdates: true);
      }
      setState(() {
        _log.add("Scanning: $state");
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _scanSubscription.cancel();
    _isScanningSubscription.cancel();
    _mtuSubscription?.cancel();
    _connectionStateSubscription?.cancel();
  }

  void _startRssiMonitoring() {
    if (_connectedDevice == null) return;
    _rssiStreamSubscription =
        _rssiStream(_connectedDevice!, const Duration(seconds: 3)).listen(
            (rssiValue) {
      setState(() {
        rssi = rssiValue;
      });
      if (rssiValue < disconnectRsiTreshold) {
        if (_disconnectTimer == null) {
          _log.add("RSSI below threshold. Starting disconnect timer...");
          _disconnectTimer = Timer(const Duration(seconds: 5), () {
            _log.add("Disconnecting due to low RSSI.");
            _disconnectTimer = null;
            _disconnect();
          });
        }
      } else {
        if (_disconnectTimer != null) {
          _log.add("RSSI above threshold. Cancelling disconnect timer.");
          _disconnectTimer!.cancel();
          _disconnectTimer = null;
        }
      }
    }, onError: (error) {
      _log.add("RSSI Stream Error: $error");
      _disconnect();
    }, onDone: () {
      _log.add("RSSI Stream Done");
    });
  }

  void _stopRssiMonitoring() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _rssiStreamSubscription?.cancel();
    _rssiStreamSubscription = null;
  }

  void automaticConnect(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
    });
    await device.connectAndUpdateStream().catchError((e) {
      setState(() {
        _log.add("Connection error: $e");
      });
      return;
    });
    _connectedDevice = device;
    setState(() {
      _log.add("Connected to ${device.advName}");
    });

    _connectionStateSubscription =
        _connectedDevice?.connectionState.listen((state) async {
      _connectionState = state;
      if (_connectionState == BluetoothConnectionState.connected) {
        setState(() {
          _connectedDevice ??= device;
          _isConnecting = false;
        });
        await _requestMtu();
        await _discoverServices();
        _startRssiMonitoring();
      }
      if (state == BluetoothConnectionState.disconnected) {
        _log.add("Device has been disconnected.");
        _connectedDevice = null;
      }
    });

    _mtuSubscription = _connectedDevice?.mtu.listen((mtu) {
      mtsuSize = mtu;
      setState(() {
        _log.add("MTU Size: $mtu");
      });
    });
  }

  Future<void> _requestMtu() async {
    if (_connectedDevice == null) return;
    try {
      await _connectedDevice!.requestMtu(223, predelay: 0);
      setState(() {
        _log.add("Requested MTU Size: 223");
      });
    } catch (e) {
      _log.add("Error requesting MTU: $e");
    }
  }

  // Discover services and characteristics
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;

    List<BluetoothService> services =
        await _connectedDevice!.discoverServices();

    for (BluetoothService service in services) {
      // Common ELM327 BLE Service UUID
      print(service.uuid.toString());
      if (service.uuid == targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            _writeCharacteristic = c;
            _log.add("Write Characteristic found: ${c.uuid}");
          }
          if (c.properties.notify) {
            _notifyCharacteristic = c;
            _log.add("Notify Characteristic found: ${c.uuid}");
            await c.setNotifyValue(true);
            c.lastValueStream.listen(_handleReceivedData);
          }
        }
      }
    }
    if (_writeCharacteristic != null && _notifyCharacteristic != null) {
      _log.add("Characteristics ready. Initializing Dongle...");
      _initializeELM327();
    } else {
      _log.add("Required characteristics not found.");
    }

    setState(() {});
  }

  // Initialize ELM327 device with necessary commands
  Future<void> _initializeELM327() async {
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
      await _sendCommand(cmd);
      await Future.delayed(
          const Duration(milliseconds: 500)); // Wait for response
    }
    _log.add("ELM327 Initialized.");
  }

  // Send an OBD-II command
  Future<void> _sendCommand(String command) async {
    if (_writeCharacteristic == null) {
      _log.add("Write Characteristic is null.");
      return;
    }

    String fullCommand = "$command\r";
    List<int> bytes = utf8.encode(fullCommand);
    try {
      await _writeCharacteristic!.write(bytes, withoutResponse: true);
      _log.add("Sent: $command");
    } catch (e) {
      _log.add("Error sending command '$command': $e");
    }
    setState(() {});
  }

  // Handle received data from notify characteristic
  void _handleReceivedData(List<int> data) {
    String response = utf8.decode(data).trim();
    _log.add("Received: $response");
    if (response.isEmpty) {
      _log.add("Empty response.");
    }

    // VIN
    if (response.startsWith("41 0C") || response.startsWith("410C")) {
      carVin = CarUtils.getCarVin(response);
    }

    // Car Mileage
    if (response.contains("10E0") || response.contains("10 E0")) {
      carKm = CarUtils.getCarKm(response);
      _log.add("Car KM: $carKm");
    }

    setState(() {});
  }

  // Disconnect from the device
  Future<void> _disconnect() async {
    try {
      await _connectedDevice!.disconnectAndUpdateStream(queue: true);
      _log.add("Disconnected from device.");
      _stopRssiMonitoring();
      setState(() {
        _writeCharacteristic = null;
        _notifyCharacteristic = null;
        _connectedDevice = null;
        _isScanning = false;
        if (_connectedDevice != null) {
          _connectedDevice = null;
        }
      });
    } catch (e) {
      _log.add("Error disconnecting: $e");
    }
  }

  // Build the UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OBD-II Flutter App"),
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.power_off),
              onPressed: _disconnect,
            )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, index) {
                  return Text(_log[index]);
                },
              ),
            ),
            if (_connectedDevice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ElevatedButton(
                  onPressed: () => _sendCommand("0902"),
                  child: const Text("Request VIN"),
                ),
              ),
            if (_connectedDevice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ElevatedButton(
                  onPressed: () => _sendCommand("2210E01"),
                  child: const Text("Request Kilometers"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
