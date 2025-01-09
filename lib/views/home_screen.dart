import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class Home extends ConsumerStatefulWidget {
  const Home({super.key});

  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> {
  final List<String> _logs = [];
  late final StreamSubscription<String> _logSubscription;

  @override
  void initState() {
    super.initState();
    final bluetoothService = ref.read(customBluetoothServiceProvider);
    _logSubscription = bluetoothService.logStream.listen((log) {
      setState(() {
        _logs.add(log);
        if (_logs.length > 15) {
          _logs.removeAt(0);
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
    final bluetoothService = ref.watch(customBluetoothServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("ELM327 Trip Tracker"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
                onPressed: () async {
                  try {
                    await bluetoothService.scanForDevices();
                  } catch (e) {
                    setState(() {
                      _logs.add("Error scanning for devices: $e");
                      if (_logs.length > 15) {
                        _logs.removeAt(0);
                      }
                    });
                  }
                },
                child: const Text("Scan and add new Devices!")),
          ),
          // Display Logs
          Expanded(
            child: _logs.isNotEmpty
                ? ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_logs[index]),
                      );
                    },
                  )
                : const Center(child: Text("No logs yet.")),
          ),
        ],
      ),
    );
  }
}
