import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import '../utils/extra.dart';
import 'elm327_services.dart';

class CustomBluetoothService {
  final StreamController<List<String>> _logStreamController =
      StreamController<List<String>>.broadcast();
  Stream<List<String>> get logStream => _logStreamController.stream;

  BluetoothDevice? _connectedDevice;
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<int>? _mtuSubscription;
  StreamSubscription<int>? _rssiStreamSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  late StreamSubscription<List<ScanResult>> _scanSubscription;
  late StreamSubscription<bool> _isScanningSubscription;
  final Guid _targetService = Guid("0000fff0-0000-1000-8000-00805f9b34fb");
  Timer? _disconnectTimer;
  final int _disconnectRssiThreshold = -90;
  final int _connectRssiTreshold = -80;
  bool _isConnecting = false;
  bool _isScanning = false;
  int? rssi;
  int? mtuSize;
  Elm327Service? elm327Service;
  final List<String> knownRemoteIds = ["8C:DE:52:DE:CB:DC"];

  CustomBluetoothService._internal() {
    FlutterBluePlus.setOptions(restoreState: true);
    _initialize();
  }
  static final CustomBluetoothService _instance =
      CustomBluetoothService._internal();
  factory CustomBluetoothService() => _instance;

  _initialize() {
    FlutterBluePlus.setOptions(restoreState: true);
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (knownRemoteIds.contains(r.device.remoteId.str)) {
          if (r.rssi > _connectRssiTreshold &&
              _isConnecting == false &&
              _connectedDevice == null) {
            _logStreamController
                .add(["Found Device has acceptable RSSI: ${r.rssi}"]);
            _connectToDevice(r.device);
            break;
          }
        }
      }
    }, onError: (e) {
      _logStreamController.add(["Scan error: $e"]);
    });
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      _isScanning = state;
      if (_isScanning == false && _connectedDevice == null) {
        FlutterBluePlus.startScan(
            timeout: const Duration(seconds: 10), continuousUpdates: true);
      }
      _logStreamController.add(["Scanning: $state"]);
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      _logStreamController.add(["Connecting to ${device.remoteId}..."]);
      await device.connectAndUpdateStream().catchError((e) {
        _logStreamController.add(["Connection error: $e"]);
        _isConnecting = false;
        return;
      });
      _connectionStateSubscription =
          _connectedDevice?.connectionState.listen((state) async {
        _connectionState = state;
        _logStreamController.add(["Connection State: $state"]);
        if (_connectionState == BluetoothConnectionState.connected) {
          _connectedDevice = device;
          await _requestMtu();
          await _discoverServices();
          _startRssiMonitoring(const Duration(seconds: 3));
          _logStreamController.add(["Connected to ${device.advName}"]);
        }
        if (_connectionState == BluetoothConnectionState.disconnected) {
          _disconnectDevice();
          _logStreamController.add(["Disconnected from ${device.remoteId}"]);
        }
        _isConnecting = false;
      });
      _mtuSubscription = _connectedDevice?.mtu.listen((mtu) {
        mtuSize = mtu;
        _logStreamController.add(["MTU Size: $mtu"]);
      });
    } catch (e) {
      _isConnecting = false;
      _logStreamController.add(["Connection error: $e"]);
    }
  }

  // Discover services and characteristics
  Future<void> _discoverServices() async {
    if (_connectedDevice == null) return;
    List<BluetoothService> services =
        await _connectedDevice!.discoverServices();
    for (BluetoothService service in services) {
      print(service.uuid.toString());
      if (service.uuid == _targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            _writeCharacteristic = c;
            _logStreamController.add(["Write Characteristic found: ${c.uuid}"]);
          }
          if (c.properties.notify) {
            _notifyCharacteristic = c;
            _logStreamController
                .add(["Notify Characteristic found: ${c.uuid}"]);
            await c.setNotifyValue(true);
          }
        }
      }
    }
    if (_writeCharacteristic != null && _notifyCharacteristic != null) {
      _logStreamController
          .add(["Characteristics ready. Initializing Dongle..."]);
      elm327Service = Elm327Service(_connectedDevice!);
      _notifyCharacteristic!.lastValueStream
          .listen(elm327Service!.handleReceivedData);
    } else {
      _logStreamController.add(["Required characteristics not found."]);
    }
  }

  Future<void> _requestMtu() async {
    if (_connectedDevice == null) return;
    try {
      await _connectedDevice!.requestMtu(223, predelay: 0);
      _logStreamController.add(["Requested MTU Size: 223"]);
    } catch (e) {
      _logStreamController.add(["Error requesting MTU: $e"]);
    }
  }

  Future<void> _disconnectDevice() async {
    try {
      _logStreamController
          .add(["Disconnecting from ${_connectedDevice!.remoteId}..."]);
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnectAndUpdateStream(queue: true);
      }
      stopRssiMonitoring();
      _connectedDevice!.cancelWhenDisconnected(_connectionStateSubscription!,
          delayed: true, next: true);
      _writeCharacteristic = null;
      _notifyCharacteristic = null;
      _connectedDevice = null;
      _logStreamController.add(["Disconnected successfully."]);
    } catch (e) {
      _logStreamController.add(["Error disconnecting: $e"]);
    }
  }

  Stream<int> _rssiStream(BluetoothDevice device, Duration interval) async* {
    while (true) {
      try {
        int rssiValue = await device.readRssi();
        yield rssiValue;
      } catch (e) {
        _logStreamController.add(["Error reading RSSI: $e"]);
        await _disconnectDevice();
        break;
      }
      await Future.delayed(interval);
    }
  }

  void _startRssiMonitoring(Duration interval) {
    if (_connectedDevice == null) return;
    _rssiStreamSubscription =
        _rssiStream(_connectedDevice!, interval).listen((rssiValue) {
      _logStreamController.add(["RSSI: $rssiValue"]);
      if (rssiValue < _disconnectRssiThreshold) {
        if (_disconnectTimer == null) {
          _logStreamController
              .add(["RSSI below threshold. Starting disconnect timer..."]);
          _disconnectTimer = Timer(const Duration(seconds: 5), () {
            _logStreamController.add(["Disconnecting due to low RSSI."]);
            _disconnectTimer = null;
            _disconnectDevice();
          });
        }
      } else {
        if (_disconnectTimer != null) {
          _logStreamController
              .add(["RSSI above threshold. Cancelling disconnect timer."]);
          _disconnectTimer?.cancel();
          _disconnectTimer = null;
        }
      }
    }, onError: (error) {
      _logStreamController.add(["RSSI Stream Error: $error"]);
      _disconnectDevice();
    }, onDone: () {
      _logStreamController.add(["RSSI Stream Done"]);
    });
  }

  void stopRssiMonitoring() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _rssiStreamSubscription?.cancel();
    _rssiStreamSubscription = null;
  }

  void dispose() {
    _logStreamController.close();
    _mtuSubscription?.cancel();
    _scanSubscription.cancel();
    _isScanningSubscription.cancel();
    _connectionStateSubscription?.cancel();
  }
}
