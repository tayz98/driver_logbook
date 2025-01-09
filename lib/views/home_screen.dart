import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String> logs = [];
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
                    logs.add("Error scanning for devices: $e");
                  }
                },
                child: const Text("Scan and add new Devices!")),
          ),
          // Display Logs
          Expanded(
            child: StreamBuilder<String>(
              stream: bluetoothService.logStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  List<String> logs = [];
                  logs = snapshot.data!.split('\n');
                  if (logs.length > 15) {
                    logs = logs.sublist(logs.length - 15);
                  }

                  return ListView(
                    children: [
                      for (var log in logs)
                        ListTile(
                          title: Text(log),
                        ),
                    ],
                  );
                } else if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                } else {
                  return const Center(child: Text("No logs yet."));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
