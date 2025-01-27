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
  // Singleton
  TripController._internal();
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;
  late final SharedPreferences _prefs;

  static final TripController _instance = TripController._internal();
  factory TripController() => _instance;
  static Future<TripController> initialize() async {
    _instance._prefs = await SharedPreferences.getInstance();
    return _instance;
  }

  void startTrip(int? mileage, Vehicle? vehicle, TripLocation? startLocation) {
    _instance._prefs.reload();
    _currentTrip = Trip(
      startMileage: mileage,
      vehicleJson: jsonEncode(vehicle?.toJson()),
      tripCategory: TripCategory
          .values[_instance._prefs.getInt('tripCategory2') ?? 0]
          .toString(),
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
    CustomLogger.i('Trip ended: ${jsonEncode(_currentTrip!.toJson())}');
    TripRepository.saveTrip(_currentTrip!);
    _currentTrip = null;
  }
}
