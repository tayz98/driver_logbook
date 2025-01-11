import 'package:elogbook/models/trip.dart';
import 'package:flutter/material.dart';

Widget buildTripDetails(BuildContext context, Trip trip) {
  return Card(
    elevation: 4,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trip Status
          Row(
            children: [
              const Icon(Icons.directions_car, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Status: ${trip.tripStatus.toString()}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
      ),
    ),
  );
}
