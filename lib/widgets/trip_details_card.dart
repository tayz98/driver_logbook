import 'package:elogbook/models/trip.dart';
import 'package:elogbook/models/trip_status.dart';
import 'package:flutter/material.dart';
import 'package:elogbook/utils/help.dart';

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
                Helper.formatDateString(trip.startTimestamp),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(),
          // Conditionally display widgets based on trip.tripStatus
          trip.tripStatus != TripStatus.notStarted.toString()
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                          'Startkilometerstand: ${trip.startMileage == 0 ? "" : "${trip.startMileage}km"}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // End Mileage
                    if (trip.endMileage != null)
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'Endkilometerstand: ${trip.endMileage}km',
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
                          'Fahrtkategorie: ${Helper.formatCategory(trip.tripCategory)}',
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
                                ? 'Startstandort: ${trip.startLocation.target!.street}, ${trip.startLocation.target!.city}, ${trip.startLocation.target!.postalCode}'
                                : '',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),

                    // End Location
                    if (trip.endLocation.target != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ankunft: ${trip.endLocation.target!.street}, ${trip.endLocation.target!.city}, ${trip.endLocation.target!.postalCode}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),

                    // Start Timestamp
                    if (trip.startTimestamp.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.access_time, color: Colors.brown),
                          const SizedBox(width: 8),
                          Text(
                            'Startzeitpunkt: ${Helper.formatDateString(trip.startTimestamp)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),

                    // End Timestamp
                    if (trip.endTimestamp != null)
                      Row(
                        children: [
                          const Icon(Icons.access_time, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(
                            'Endzeitpunkt: ${Helper.formatDateString(trip.endTimestamp!)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                  ],
                )
              : Container(), // Show nothing if trip.tripStatus == TripStatus.notStarted
        ],
      ),
    ),
  );
}
