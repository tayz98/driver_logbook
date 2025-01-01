import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/snackbar.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/extra.dart';
import 'device_screen.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

// this widget is the entry point where a user can scan for devices
class _HomeState extends State<Home> {
  BluetoothAdapterState _adapterState =
      BluetoothAdapterState.unknown; // initial state
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  static const String deviceMac = "8C:DE:52:DE:CB:DC";
  late StreamSubscription<List<ScanResult>> _scanResultSubscription;
  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    // check if the adapter is on, if not, prompt the user to turn it on
    FlutterBluePlus.startScan();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      if (mounted) {
        setState(() {});
      }
    });
    _scanResultSubscription = FlutterBluePlus.scanResults.listen((results) {
      // store the scan results
      _scanResults = results;
      if (mounted) {
        setState(() {});
      }
    }, onError: (e) {
      Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      print(e);
      print("Error scanning for devices");
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription.cancel();
    _scanResultSubscription.cancel();
    super.dispose();
  }

  // for the future: repeat the connection attempt until successful
  void connectDevice() async {
    try {
      print("call function: connectDevice");
      // Assuming _scanResults is populated during the scan
      if (_scanResults.isEmpty) {
        print("No devices found");
        Snackbar.show(ABC.b, "No devices found", success: false);
        return;
      }

      for (ScanResult result in _scanResults) {
        debugPrint(result.device.advName);
        debugPrint(result.device.remoteId.toString().toUpperCase());
        if (deviceMac == result.device.remoteId.toString().toUpperCase()) {
          print("Device found: ${result.device.advName}");

          // Attempt to connect to the device
          await result.device.connect();
          print("Device connected");

          // Stop scanning after connecting
          await FlutterBluePlus.stopScan();

          // Navigate to the next screen
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeviceScreen(device: result.device),
              ),
            );
          }
          return; // Exit after connecting to the target device
        }
      }

      // If no matching device found
      print("No matching device found");
      Snackbar.show(ABC.b, "No matching device found", success: false);
    } catch (e) {
      print("Error during connection: $e");
      Snackbar.show(ABC.b, prettyException("Connection Error:", e),
          success: false);
    } finally {
      // Ensure the scan is stopped in case of errors
      await FlutterBluePlus.stopScan();
    }
  }

  Widget buildScanButton(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ElevatedButton(
            onPressed: connectDevice,
            child: const Text('Connect to Device'),
          ),
        ],
      ),
    );
  }

  // what should happen here:
  // if a device is connected, switch to the DeviceScreen, else show "not found"
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _adapterState == BluetoothAdapterState.on
          ? buildScanButton(context)
          : const Center(
              child: Text("Bluetooth is off, turn it on to scan devices"),
            ),
    );
  }
}
