import 'dart:async';

import 'package:elogbook/services/custom_bluetooth_service.dart';
import 'package:flutter/material.dart';
import 'package:elogbook/notification_configuration.dart'; // Import the notification service

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final CustomBluetoothService _bluetoothService = CustomBluetoothService();
  final List<String> _logs = [];
  late StreamSubscription<List<String>> _logSubscription;
  @override
  void initState() {
    super.initState();
    showBasicNotification(
        title: "TestNotification", body: "This is a test notification");
    // Listen to the logStream and update the UI accordingly
    _bluetoothService.logStream.listen((logList) {
      setState(() {
        _logs.addAll(logList);
      });
    });
    _logSubscription = _bluetoothService.logStream.listen((logList) {
      setState(() {
        _logs.addAll(logList);

        if (_logs.length > 100) {
          _logs.removeRange(0, _logs.length - 10);
        }
      });
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OBD-II Flutter App"),
      ),
      body: _logs.isEmpty
          ? const Center(child: Text("No logs available"))
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return ListTile(
                  dense: true, // Makes the ListTile denser
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0, // Reduced vertical padding
                  ),
                  title: Text(
                    _logs[index],
                    style: const TextStyle(
                      fontSize: 14.0, // Smaller font size
                    ),
                  ),
                );
              },
            ),
    );
  }
}
