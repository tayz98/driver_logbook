import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'elm327_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomBluetoothService {
  // Streams
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();
  Stream<String> get logStream => _logStreamController.stream;

  // Subscriptions
  StreamSubscription<int>? _rssiStreamSubscription;
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription;
  // Bluetooth
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastConnectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothConnectionState? _connectionState;
  final Guid _targetService = Guid("0000fff0-0000-1000-8000-00805f9b34fb");

  // Elm327
  Elm327Service? elm327Service;

  // misc variables
  final String _targetAdvName = "VEEPEAK";
  Timer? _disconnectTimer;
  final int _disconnectRssiThreshold = -150;
  late SharedPreferences prefs;
  //final int _rssiTresholdForElm327Service = -100;

  CustomBluetoothService() {
    FlutterBluePlus.setOptions(restoreState: true);
    _initialize();
  }

  Future<void> _initialize() async {
    prefs = await SharedPreferences.getInstance();
    await _loadSavedDeviceIds();
    await _fetchDevicesFromIds();

    _connectionStateSubscription =
        FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      _connectionState = event.connectionState;
      if (_connectionState == BluetoothConnectionState.connected) {
        _logStreamController.add(
            "Connected to ${event.device.remoteId.str} and Name: ${event.device.advName}.");
        _connectedDevice = event.device;
        //final int currentRssi = await _connectedDevice!.readRssi();
        // if (currentRssi < _rssiTresholdForElm327Service) {
        //   _logStreamController
        //       .add("RSSI below threshold for ELM327 Service. Disconnecting...");
        //   _connectionState = BluetoothConnectionState.disconnected;
        // }
        await _requestMtu(_connectedDevice!); // not supported on iOS
        await _discoverCharacteristics(_connectedDevice!);
        _trackRssi(
            dev: _connectedDevice!, interval: const Duration(seconds: 5));
      } else if (_connectionState == BluetoothConnectionState.disconnected) {
        _logStreamController
            .add("Disconnected from ${event.device.remoteId.str}");
        await _disposeConnection(_connectedDevice!);

        // needed because when disconnect() is used on autoConnect
        // the device is not auto connecting anymore
        await _lastConnectedDevice?.connect(autoConnect: true, mtu: null);
      }
    });
  }

  void dispose() {
    _logStreamController.close();
    _connectionStateSubscription?.cancel();
    _rssiStreamSubscription?.cancel();
    _lastConnectedDevice?.disconnect();
  }

  Future<void> _disposeConnection(BluetoothDevice dev) async {
    _lastConnectedDevice = dev;
    elm327Service?.dispose();
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    await _rssiStreamSubscription?.cancel();
    await dev.disconnect();
  }

  Stream<int> _rssiStream(BluetoothDevice device, Duration interval) async* {
    while (true) {
      try {
        int rssiValue = await device.readRssi();
        yield rssiValue;
      } catch (e) {
        _logStreamController.add("Error reading RSSI: $e");
        break;
      }
      await Future.delayed(interval);
    }
  }

  void _trackRssi({required BluetoothDevice dev, required Duration interval}) {
    _rssiStreamSubscription = _rssiStream(dev, interval).listen((rssiValue) {
      if (rssiValue < _disconnectRssiThreshold) {
        if (_disconnectTimer == null) {
          _logStreamController
              .add("RSSI below threshold. Starting disconnect timer...");
          _disconnectTimer = Timer(const Duration(seconds: 5), () {
            _logStreamController.add("Disconnecting due to low RSSI.");
            _disconnectTimer = null;
            _connectionState = BluetoothConnectionState.disconnected;
          });
        }
      } else {
        if (_disconnectTimer != null) {
          _logStreamController
              .add("RSSI above threshold. Cancelling disconnect timer.");
          _disconnectTimer?.cancel();
          _disconnectTimer = null;
        }
      }
    }, onError: (error) {
      _logStreamController.add("RSSI Stream Error: $error");
    });
  }

  Future<void> _fetchDevicesFromIds() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getStringList('knownRemoteIds') == null) {
      _logStreamController.add("Storage with IDs empty");
      return;
    }

    for (var id in prefs.getStringList('knownRemoteIds')!) {
      _logStreamController.add("Attempting to connect to device ID: $id");
      try {
        final device = BluetoothDevice.fromId(id);
        await device.connect(autoConnect: true, mtu: null);
        _logStreamController.add("Connected to device ID: $id");
      } catch (e) {
        _logStreamController
            .add("Failed to connect to device ID: $id. Error: $e");
      }
    }
  }

  Future<void> _saveDeviceIds(List<String> deviceIds) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getStringList('knownRemoteIds') == null) {
      await prefs.setStringList('knownRemoteIds', []);
      _logStreamController.add("Created knownRemoteIds list.");
    }
    final List<String> knownRemoteIds = prefs.getStringList('knownRemoteIds')!;
    for (var id in deviceIds) {
      if (!knownRemoteIds.contains(id)) {
        knownRemoteIds.add(id);
        _logStreamController.add("Saved device ID: $id");
      }
    }
    await prefs.setStringList('knownRemoteIds', knownRemoteIds);
  }

  Future<void> _loadSavedDeviceIds() async {
    prefs.getStringList('knownRemoteIds') ?? [];
  }

  Future<void> scanForDevices() async {
    final List<String> deviceIds = [];
    _logStreamController.add("Starting scan...");

    try {
      await FlutterBluePlus.startScan(
          withServices: [_targetService],
          withNames: [_targetAdvName],
          timeout: const Duration(seconds: 5));
      FlutterBluePlus.scanResults.listen((results) async {
        for (var result in results) {
          _logStreamController.add("Found Device: ${result.device.advName}");
          _logStreamController.add("Device ID: ${result.device.remoteId.str}");
          deviceIds.add(result.device.remoteId.str);
        }
      });
      _logStreamController.add("Scan completed.");
      await _saveDeviceIds(deviceIds);
      await _fetchDevicesFromIds();
    } catch (e) {
      _logStreamController.add("Error during scanning: $e");
    }
  }

  Future<void> _requestMtu(BluetoothDevice dev) async {
    try {
      await dev.requestMtu(128, predelay: 0);
      _logStreamController.add("Requested MTU Size: 128");
    } catch (e) {
      _logStreamController.add("Error requesting MTU: $e");
    }
  }

  Future<void> _discoverCharacteristics(BluetoothDevice dev) async {
    List<BluetoothService> services = await dev.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == _targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            _writeCharacteristic = c;
            _logStreamController.add("Write Characteristic found: ${c.uuid}");
          }
          if (c.properties.notify) {
            _notifyCharacteristic = c;
            _logStreamController.add("Notify Characteristic found: ${c.uuid}");
          }
        }
      }
    }

    if (_writeCharacteristic != null && _notifyCharacteristic != null) {
      elm327Service ??= Elm327Service(
        _connectedDevice!,
        _writeCharacteristic!,
        _notifyCharacteristic!,
      );
      _logStreamController.add("Characteristics ready. Initializing Dongle...");
      await _notifyCharacteristic!.setNotifyValue(true);
      elm327Service?.logStream.listen((logMessage) {
        _logStreamController.add(logMessage);
      });
      _notifyCharacteristic!.lastValueStream
          .listen(elm327Service!.handleReceivedData);
    }
  }
}
