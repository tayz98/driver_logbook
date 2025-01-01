import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/extra.dart';
import '../utils/snackbar.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: widget.device.connectionState,
      builder: (context, snapshot) {
        final connectionState =
            snapshot.data ?? BluetoothConnectionState.disconnected;
        if (connectionState == BluetoothConnectionState.connected) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                      'Connected to ${widget.device.advName} with ID: ${widget.device.remoteId}'),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await widget.device.disconnectAndUpdateStream();
                        Snackbar.show(ABC.b, 'Device disconnected',
                            success: true);
                      } catch (e) {
                        Snackbar.show(
                            ABC.b, prettyException("Disconnect Error:", e),
                            success: false);
                        print(e);
                      }
                    },
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ),
          );
        } else {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text('Device ${widget.device.advName} is disconnected'),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        Navigator.of(context).pop();
                      } catch (e) {
                        Snackbar.show(
                            ABC.b, prettyException("Navgiator error:", e),
                            success: false);
                        print(e);
                      }
                    },
                    child: const Text('Not connected, go back'),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}
