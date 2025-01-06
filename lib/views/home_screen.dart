import 'package:flutter/material.dart';
import 'package:elogbook/notification_configuration.dart';
import '../services/custom_bluetooth_service.dart';
import 'dart:async';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final CustomBluetoothService _bluetoothService = CustomBluetoothService();
  final List<String> _logs = [];
  late StreamSubscription<String> _logSubscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    showBasicNotification(
        title: "TestNotification", body: "This is a test notification");

    _logSubscription = _bluetoothService.logStream.listen((logMessage) {
      if (logMessage.isNotEmpty) {
        setState(() {
          _logs.add(logMessage);
        });
      }
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    _scrollController.dispose(); // Dispose of the ScrollController
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
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: ListView.builder(
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_logs[index]),
                  );
                },
              ),
            ),
    );
  }
}
