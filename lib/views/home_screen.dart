// lib/views/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart'; // Ensure correct path
import '../models/trip.dart'; // Adjust as necessary

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripNotifierProvider);
    final bluetoothService = ref
        .watch(customBluetoothServiceProvider); // Use watch if UI depends on it

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
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(snapshot.data!),
                      ),
                    ],
                  );
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
