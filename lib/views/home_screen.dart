import 'dart:async';
import 'package:elogbook/models/trip.dart';
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
    final tripNotifier = ref.watch(tripProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text("ELM327 Trip Tracker"),
      ),
      body: Column(
        children: [
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildTripDetails(context, tripNotifier.trip),
            ),
          ),
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

  Widget _buildTripDetails(BuildContext context, Trip trip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trip Status
        Row(
          children: [
            const Icon(Icons.directions_car, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              'Status: ${trip.tripStatus.toString()}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const Divider(),
        // VIN
        Row(
          children: [
            const Icon(Icons.vpn_key, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'VIN: ${trip.vin}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Start Mileage
        Row(
          children: [
            const Icon(Icons.speed, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Start Mileage: ${trip.startMileage}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // End Mileage (if available)
        if (trip.endMileage != null)
          Row(
            children: [
              const Icon(Icons.speed, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'End Mileage: ${trip.endMileage}',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        if (trip.endMileage != null) const SizedBox(height: 8),

        // Trip Category
        Row(
          children: [
            const Icon(Icons.category, color: Colors.purple),
            const SizedBox(width: 8),
            Text(
              'Category: ${trip.tripCategoryEnum.toString().split('.').last}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Start Location
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.place, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                trip.startLocation.target != null
                    ? 'Start Location: ${trip.startLocation.target!.street}, ${trip.startLocation.target!.city}, ${trip.startLocation.target!.postalCode}'
                    : 'Start Location: Not Set',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        if (trip.endLocation.target != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'End Location: ${trip.endLocation.target!.street}, ${trip.endLocation.target!.city}, ${trip.endLocation.target!.postalCode}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),

        // Start Timestamp
        Row(
          children: [
            const Icon(Icons.access_time, color: Colors.brown),
            const SizedBox(width: 8),
            Text(
              'Start: ${trip.startTimestamp}',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // End Timestamp (if available)
        if (trip.endTimestamp != null)
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                'End: ${trip.endTimestamp}',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
      ],
    );
  }
}
