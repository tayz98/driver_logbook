import 'dart:convert';

import 'package:driver_logbook/models/trip.dart';
import 'package:driver_logbook/models/trip_category.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/models/vehicle.dart';
import 'package:driver_logbook/repositories/trip_repository.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TripController {
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;

  late SharedPreferences _prefs;

  TripController() {
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
    });
  }

  void startTrip(int mileage, Vehicle vehicle, TripLocation startLocation) {
    _prefs.reload();
    _currentTrip = Trip(
      startMileage: mileage,
      vehicleJson: jsonEncode(vehicle.toJson()),
      tripCategory:
          TripCategory.values[_prefs.getInt('tripCategory2') ?? 0].toString(),
      tripStatus: TripStatus.inProgress.toString(),
      startLocationJson: jsonEncode(startLocation.toJson()),
    );
  }

  void changeCategory(TripCategory newCategory) async {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    }
    await _prefs.setInt(
        'tripCategory2', TripCategory.values.indexOf(newCategory));
  }

  // status = finished -> trip ended successfully
  // status = cancelled -> bluetooth connection lost
  void endTrip(TripLocation? endLocation, int mileage, TripStatus status) {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    }
    _currentTrip!.tripStatus = TripStatus.finished.toString();
    if (endLocation == null) {
      debugPrint("End location not found");
      _currentTrip!.endLocationJson = jsonEncode(TripLocation(
              street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt")
          .toJson());
    } else {
      _currentTrip!.endLocationJson = jsonEncode(endLocation.toJson());
    }
    _currentTrip!.endTimestamp = DateTime.now().toIso8601String();
    _currentTrip!.endMileage = mileage;
    _currentTrip!.tripStatus = status.toString();
    TripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }
}
