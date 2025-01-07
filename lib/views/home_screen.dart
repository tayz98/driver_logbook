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
          // Display Logs
          Expanded(
            child: StreamBuilder<String>(
              stream: bluetoothService.logStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  // Add new log to the list
                  logs.add(snapshot.data!);

                  return ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(logs[index]),
                      );
                    },
                  );
                } else if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else {
                  return const Center(child: Text("No logs available."));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
