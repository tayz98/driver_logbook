import 'dart:async';
import 'package:driver_logbook/models/telemetry_bus.dart';
import 'package:driver_logbook/models/telemetry_event.dart';
import 'package:driver_logbook/services/elm327_service.dart';
import 'package:driver_logbook/controllers/trip_controller.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:driver_logbook/utils/extra.dart';
import 'package:driver_logbook/utils/vehicle_utils.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:driver_logbook/objectbox.dart';

class IosBluetoothService {
  static final IosBluetoothService _instance = IosBluetoothService._internal();
  factory IosBluetoothService() => _instance;
  StreamSubscription<OnConnectionStateChangedEvent>?
      _connectionStateSubscription; // for handling connection states
  StreamSubscription<List<int>>?
      _dataSubscription; // for obversing incoming data from elm327
  StreamSubscription<List<ScanResult>>?
      _scanResultsSubscription; //  for handling scan results
  late Guid targetService; // target service for scanning
  late String targetName; // target name for scanning
  List<String> knownRemoteIds = []; // list of known remote ids to connect to
  late SharedPreferences _prefs; // used for storing persistent data
  Elm327Service? _elm327Service; // ELM327 service
  // Timer:
  Timer? _scanTimer; // timer to scan for devices if disconnected

  IosBluetoothService._internal() {
    _initialize();
  }

  // create all necessary data
  Future<void> _initializeData() async {
    await dotenv.load(fileName: ".env");
    targetName = dotenv.get("TARGET_ADV_NAME", fallback: "");
    targetService = Guid(dotenv.get('TARGET_SERVICE', fallback: ''));
    CustomLogger.d('Initialized dotenv');

    CustomLogger.d('Initializing data...');
    _prefs = await SharedPreferences.getInstance();
    CustomLogger.d('Initialized SharedPreferences');
    try {
      await ObjectBox.create();
      CustomLogger.d('Initialized ObjectBox');
    } catch (e) {
      CustomLogger.e('ObjectBox error: $e');
    }
    knownRemoteIds = _prefs.getStringList("knownRemoteIds") ?? [];
    CustomLogger.d('Initialized knownRemoteIds');
    await TripController.initialize();
    CustomLogger.d('Initialized TripController');
    await VehicleUtils.initializeVehicleModels();
    CustomLogger.d('Initialized VehicleModels');
  }

  // find new devices
  Future<void> _scanDevices() async {
    try {
      CustomLogger.d("Scanning for devices...");
      await FlutterBluePlus.startScan(
          withServices: [targetService],
          withNames: [targetName],
          timeout: const Duration(seconds: 2));
    } catch (e) {
      CustomLogger.e("Error in _scanDevices: $e");
      return;
    }
  }

  void _initialize() async {
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;
    _initializeData();
    FlutterBluePlus.setOptions(restoreState: true);
    TripController.initialize();
    _scanTimer = Timer.periodic(const Duration(seconds: 50), (_) async {
      CustomLogger.d("scan timer started");
      await _scanDevices();
    });
    _connectionStateSubscription ??=
        FlutterBluePlus.events.onConnectionStateChanged.listen((event) async {
      CustomLogger.i(
          "Event Device: ${event.device}, New Connection state: $event.connectionState");
      // on every connection state change, check for the nearest device
      final tempDevice = await _findNearestDevice();
      if (event.connectionState == BluetoothConnectionState.connected) {
        if (tempDevice != null) {
          _setupConnectedDevice(tempDevice);
        }
        // if connected, cancel scans
        CustomLogger.d("BLE disconnect timer cancelled on connection");
      } else if (event.connectionState ==
          BluetoothConnectionState.disconnected) {
        if (event.device.remoteId == _elm327Service?.deviceId) {
          await Future.delayed(const Duration(seconds: 5), () async {
            if (event.device.isDisconnected) {
              // dispose service after 5 seconds
              await _disposeElmService();
            }
          });
        }

        if (!event.device.isAutoConnectEnabled) {
          // if auto connect is disabled by disconnecting, enable it again
          // this usually shouldn't happen, but for safety reasons we check it
          event.device.connectAndUpdateStream();
          CustomLogger.d("Auto connect enabled again");
        }
        if (tempDevice != null) {
          _setupConnectedDevice(tempDevice);
        }
      }
    });
    _scanResultsSubscription ??=
        FlutterBluePlus.onScanResults.listen((results) async {
      CustomLogger.i("Scan results: $results");
      if (results.isNotEmpty) {
        for (var result in results) {
          if (knownRemoteIds.contains(result.device.remoteId.str)) {
            // skip device that were already scanned
            CustomLogger.d(
                "Remote id already known: ${result.device.remoteId.str}");
            continue;
          } else {
            CustomLogger.d(
                "New remote id scanned and added: ${result.device.remoteId.str}");
            knownRemoteIds.add(result.device.remoteId.str);
            // overwrite shared preference with the new list
            _prefs.setStringList("knownRemoteIds", knownRemoteIds);
          }
        }
        // fetch scanned device(s) to initiate new connections
        await _fetchAndConnectToDevices();
      }
    });
    CustomLogger.d(
        "Fetching and connecting to devices in _initializeBluetooth");
    await _fetchAndConnectToDevices();
    CustomLogger.d("_initializeBluetooth completed");
  }

  Future<void> _disposeElmService() async {
    if (TripController().isTripInProgress) {
      CustomLogger.d("Trip in progress, not disposing controller");
      TelemetryEvent event = TelemetryEvent(voltage: 0.0);
      TelemetryBus().publish(event);
    }

    await _elm327Service?.dispose();
    _elm327Service = null;
  }

  // return the device with the best signal strength
  Future<BluetoothDevice?> _findNearestDevice() async {
    if (FlutterBluePlus.connectedDevices.isEmpty) {
      CustomLogger.d("No connected devices");
      return null;
    }
    final devices = FlutterBluePlus.connectedDevices;
    if (devices.length == 1) {
      return devices.first;
    }
    final deviceRssiMap = <BluetoothDevice, int>{};
    for (var device in devices) {
      final rssi = await device.readRssi();
      deviceRssiMap[device] = rssi;
    }

    final nearestDevice = deviceRssiMap.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
    return nearestDevice;
  }

  Future<void> _setupConnectedDevice(BluetoothDevice device) async {
    if (_elm327Service?.isTripInProgress == true) {
      // if a trip is in progress, don't set up a new connected device
      CustomLogger.d("Trip in progress, not setting up new connected device");
      return;
    } else if (_elm327Service?.isTripInProgress == false) {
      // if no trip is in progress, dispose the controller, to start a new one
      _disposeElmService();
    }

    CustomLogger.d("Setting up connected device: ${device.remoteId.str}");
    await _requestMtu(device);
    await _discoverCharacteristicsAndStartElm327(device);
  }

  Future<void> _requestMtu(BluetoothDevice device) async {
    try {
      CustomLogger.d("Requesting MTU...");
      await device.requestMtu(128, predelay: 0);
      CustomLogger.d("MTU after request: ${device.mtu}");
    } catch (e) {
      return;
    }
  }

  // auto connects to known or recently scanned devices
  Future<void> _fetchAndConnectToDevices() async {
    _prefs.reload(); // reload shared preferences if received from the main app
    CustomLogger.d("Fetching and connecting to devices...");
    CustomLogger.i("Known remote ids: $knownRemoteIds");
    if (knownRemoteIds.isEmpty) {
      CustomLogger.d("No known remote ids");
      return;
    }

    for (var id in knownRemoteIds) {
      try {
        final device = BluetoothDevice.fromId(id);
        await device.connectAndUpdateStream();
        CustomLogger.i("Starting auto connect to device: $id");
        break;
      } catch (e) {
        CustomLogger.e("Error in _fetchAndConnectToDevices: $e");
        return;
      }
    }
  }

  Future<void> _discoverCharacteristicsAndStartElm327(
      BluetoothDevice device) async {
    if (FlutterBluePlus.connectedDevices.isEmpty) {
      CustomLogger.d("Can't discover characteristics, no connected device");
      return;
    }
    CustomLogger.d("Discovering characteristics for service: $targetService");
    BluetoothCharacteristic? writeCharacteristic;
    BluetoothCharacteristic? notifyCharacteristic;
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid == targetService) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write) {
            writeCharacteristic = c;
            CustomLogger.d("Write characteristic found: ${c.uuid}");
          }
          if (c.properties.notify) {
            notifyCharacteristic = c;
            await notifyCharacteristic.setNotifyValue(true);
            CustomLogger.d("Notify characteristic found: ${c.uuid}");
          }
        }
      }
    }

    if (writeCharacteristic != null && notifyCharacteristic != null) {
      _elm327Service = Elm327Service(
          writeCharacteristic: writeCharacteristic,
          notifyCharacteristic: notifyCharacteristic,
          device: device);
      CustomLogger.i(
          "Chraracteristics found, starting ELM327 with device: ${device.remoteId.str}");
      _dataSubscription = notifyCharacteristic.lastValueStream.listen((data) {
        CustomLogger.d("Received data!");
        _elm327Service!.handleReceivedData(data);
      });
      if (_dataSubscription != null) {
        device.cancelWhenDisconnected(_dataSubscription!, delayed: true);
      }
      final initialized = await _elm327Service?.initialize() ?? false;
      if (!initialized) {
        CustomLogger.e("ELM327 initialization failed");
        device.disconnectAndUpdateStream();
      } else {
        CustomLogger.i("ELM327 successfully initialized");
        CustomLogger.d("Starting checking for voltage");
        await _elm327Service!.startVoltageTimer();
      }
    } else {
      CustomLogger.e("Characteristics not found, can't start ELM327");
    }
  }
}
