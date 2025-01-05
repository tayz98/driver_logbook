import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import "../services/custom_bluetooth_service.dart";
import '../services/elm327_services.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late CustomBluetoothService customBluetoothService;
  Elm327Service? elm327Service;
  final List<String> log = [];

  @override
  void initState() {
    super.initState();
    customBluetoothService = CustomBluetoothService(
        targetService: Guid("0000fff0-0000-1000-8000-00805f9b34fb"),
        targetMac: "8C:DE:52:DE:CB:DC");
    customBluetoothService.logStream.stream.listen((newLog) {
      setState(() {
        log.addAll(newLog);
      });
    });
  }

  @override
  void dispose() {
    customBluetoothService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("OBD-II Flutter App"),
      ),
      body: ListView.builder(itemBuilder: (context, index) {
        return ListTile(
          title: Text(log[index]),
        );
      }),
    );
  }
}
