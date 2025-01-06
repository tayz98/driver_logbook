import 'package:flutter/material.dart';
import 'package:elogbook/notification_configuration.dart';
import '../services/custom_bluetooth_service.dart';
import 'dart:async';
import '../models/driver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  final CustomBluetoothService _bluetoothService = CustomBluetoothService();
  final List<String> _logs = [];
  late StreamSubscription<String> _logSubscription;
  Driver? driver;

  @override
  void initState() {
    final driverNotifier = ref.read(driverProvider.notifier);
    driverNotifier.logIn('1');
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
    super.dispose();
  }

  void checkLogin() {
    // check if a driver exists in the database
    // if not give the user the option to create a new driver
    // if no driver is created, the app should not proceed
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
