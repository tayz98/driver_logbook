import 'dart:convert';

import 'package:driver_logbook/models/trip.dart';
import 'package:driver_logbook/models/trip_category.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/repositories/trip_repository.dart';
import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TripController {
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;
  final Store _store;
  late TripRepository _tripRepository;
  final SharedPreferences _prefs;

  TripController(this._store, this._prefs) {
    _tripRepository = TripRepository(_store);
  }

  void startTrip(int mileage, String vin, TripLocation startLocation) {
    _prefs.reload();

    _currentTrip = Trip(
      startMileage: mileage,
      vin: vin,
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

  void endTrip(TripLocation? endLocation, int mileage) {
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
    _currentTrip!.tripStatus = TripStatus.finished.toString();
    _tripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }

  // a use case could be to cancel a trip if the background task got destroyed.
  void cancelTrip(TripLocation? endLocation, int? mileage) {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    }
    if (endLocation == null) {
      debugPrint("End location not found");
      _currentTrip!.endLocationJson = jsonEncode(TripLocation(
          street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt"));
    } else {
      _currentTrip!.endLocationJson = jsonEncode(endLocation.toJson());
    }
    _currentTrip!.tripStatus = TripStatus.cancelled.toString();
    _currentTrip!.endTimestamp = DateTime.now().toIso8601String();
    if (mileage != null) _currentTrip!.endMileage = mileage;
    _tripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }

  void changeStore(Store store) {
    _tripRepository = TripRepository(store);
  }
}
