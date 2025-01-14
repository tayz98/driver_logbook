import 'package:elogbook/models/driver.dart';
import 'package:elogbook/models/trip.dart';
import 'package:elogbook/models/trip_category.dart';
import 'package:elogbook/models/trip_location.dart';
import 'package:elogbook/models/trip_status.dart';
import 'package:elogbook/objectbox.g.dart';
import 'package:elogbook/repositories/driver_repository.dart';
import 'package:elogbook/repositories/trip_repository.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TripController {
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;
  Driver? _currentDriver;
  final Store _store;
  late TripRepository _tripRepository;
  late DriverRepository _driverRepository;
  final SharedPreferences _prefs;

  TripController(this._store, this._prefs) {
    _tripRepository = TripRepository(_store);
    _driverRepository = DriverRepository(_store);
  }

  void startTrip(int mileage, String vin, TripLocation startLocation) {
    _currentDriver = _driverRepository.getDriver();
    if (_currentDriver == null) {
      debugPrint("Driver not found");
      throw Exception('Driver not found');
    }
    _currentTrip = Trip(
      driver: ToOne<Driver>()..target = _currentDriver,
      startMileage: mileage,
      vin: vin,
      tripCategory:
          TripCategory.values[_prefs.getInt('tripCategory2') ?? 0].toString(),
      tripStatus: TripStatus.inProgress.toString(),
    );
    _currentTrip!.startLocation.target = startLocation;
  }

  void changeMode(TripCategory newCategory) async {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    }
    await _prefs.setInt(
        'tripCategory2', TripCategory.values.indexOf(newCategory));
  }

  void updateMileage(int mileage) {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    } else if (mileage <= _currentTrip!.startMileage) {
      debugPrint("Mileage didn't increase");
      return;
    } else {
      _currentTrip!.currentMileage = mileage;
    }
  }

  void endTrip(TripLocation? endLocation) {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    }
    _currentTrip!.tripStatus = TripStatus.finished.toString();
    if (endLocation == null) {
      debugPrint("End location not found");
      _currentTrip!.endLocation.target = TripLocation(
          street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
    } else {
      _currentTrip!.endLocation.target = endLocation;
    }
    _currentTrip!.endTimestamp = DateTime.now().toIso8601String();
    _currentTrip!.endMileage = _currentTrip!.currentMileage;
    _currentTrip!.tripStatus = TripStatus.finished.toString();
    _tripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }

  // think about conditions for cancelling a trip
  void cancelTrip(TripLocation? endLocation) {
    if (_currentTrip == null) {
      debugPrint("Trip not found");
      throw Exception('Trip not found');
    }
    if (endLocation == null) {
      debugPrint("End location not found");
      _currentTrip!.endLocation.target = TripLocation(
          street: "Unbekannt", city: "Unbekannt", postalCode: "Unbekannt");
    } else {
      _currentTrip!.endLocation.target = endLocation;
    }
    _currentTrip!.tripStatus = TripStatus.cancelled.toString();
    _currentTrip!.endTimestamp = DateTime.now().toIso8601String();
    _currentTrip!.endMileage = _currentTrip!.currentMileage;
    _tripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }

  void changeStore(Store store) {
    _tripRepository = TripRepository(store);
    _driverRepository = DriverRepository(store);
  }
}
