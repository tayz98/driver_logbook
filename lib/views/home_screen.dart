import 'package:elogbook/providers/providers.dart';
import 'package:flutter/material.dart';
import '../models/driver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Home extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripNotifierProvider);
    final tripNotifier = ref.read(tripNotifierProvider.notifier);
    final bluetoothService = ref.watch(customBluetoothServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text("ELM327 Trip Tracker"),
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
                  return Center(child: Text("No logs available."));
                }
              },
            ),
          ),
          // Trip Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () async {
                // Example: Set the current driver before starting a trip
                // You might want to implement a proper driver selection mechanism
                final driver = Driver(); // Replace with actual driver retrieval
                tripNotifier.setDriver(driver);
                tripNotifier.startTrip();
              },
              child: Text(trip == null ? "Start Trip" : "End Trip"),
            ),
          ),
          // Display Current Trip Info
          if (trip != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "Trip Status: ${trip.tripStatus}\nVIN: ${trip.telemetry.target?.vehicleDiagnostics.target?.vin ?? 'N/A'}\nMileage: ${trip.telemetry.target?.vehicleDiagnostics.target?.currentMileage ?? 'N/A'}",
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
