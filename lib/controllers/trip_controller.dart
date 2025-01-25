import 'dart:convert';

import 'package:driver_logbook/models/trip.dart';
import 'package:driver_logbook/models/trip_category.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/models/vehicle.dart';
import 'package:driver_logbook/repositories/trip_repository.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TripController {
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;

  late SharedPreferences _prefs;

  static Future<TripController> create() async {
    final controller = TripController();
    controller._prefs = await SharedPreferences.getInstance();
    return controller;
  }

  void startTrip(int? mileage, Vehicle? vehicle, TripLocation? startLocation) {
    _prefs.reload();
    _currentTrip = Trip(
      startMileage: mileage,
      vehicleJson: jsonEncode(vehicle?.toJson()),
      tripCategory:
          TripCategory.values[_prefs.getInt('tripCategory2') ?? 0].toString(),
      tripStatus: TripStatus.inProgress.toString(),
      startLocationJson: jsonEncode(startLocation?.toJson()),
    );
  }

  void endTrip(TripLocation? endLocation, int? mileage) {
    if (_currentTrip == null) {
      CustomLogger.e("Trip not found");
      throw Exception('Trip not found');
    }
    if (mileage != null) {
      _currentTrip!.endMileage = mileage;
    }
    if (endLocation != null) {
      _currentTrip!.endLocationJson = jsonEncode(endLocation.toJson());
    }
    _currentTrip!.endTimestamp = DateTime.now().toIso8601String();
    final status = _currentTrip!.isTripCompleted()
        ? TripStatus.completed
        : TripStatus.incorrect;
    _currentTrip!.tripStatus = status.toString();
    CustomLogger.i('Trip ended: ${_currentTrip!.toJson()}');
    TripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }
}
