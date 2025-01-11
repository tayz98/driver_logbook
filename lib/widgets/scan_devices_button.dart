// elevated button widget

import 'package:flutter/material.dart';

class ScanDevicesButton extends StatefulWidget {
  final Function onPressed;

  const ScanDevicesButton({super.key, required this.onPressed});

  @override
  ScanDevicesButtonState createState() => ScanDevicesButtonState();
}

class ScanDevicesButtonState extends State<ScanDevicesButton> {
  final List<String> _logs = [];

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        try {
          await widget.onPressed();
        } catch (e) {
          setState(() {
            _logs.add("Error scanning for devices: $e");
            if (_logs.length > 15) {
              _logs.removeAt(0);
            }
          });
        }
      },
      child: const Text("Scan and Save Devices"),
    );
  }
}
