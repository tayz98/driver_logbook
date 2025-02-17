import 'dart:async';
import 'dart:convert';

import 'package:driver_logbook/models/telemetry_bus.dart';
import 'package:driver_logbook/models/telemetry_event.dart';
import 'package:driver_logbook/models/trip.dart';
import 'package:driver_logbook/models/trip_category.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/models/vehicle.dart';
import 'package:driver_logbook/repositories/trip_repository.dart';
import 'package:driver_logbook/services/gps_service.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TripController {
  // Singleton
  TripController._internal();
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;
  int? _currentMileage;
  late final SharedPreferences _prefs;
  late final StreamSubscription<TelemetryEvent> _subscription;

  static final TripController _instance = TripController._internal();
  factory TripController() => _instance;
  static Future<TripController> initialize() async {
    _instance._prefs = await SharedPreferences.getInstance();
    _instance._subscription =
        TelemetryBus().stream.listen(_instance._handleTelemetryEvent);

    return _instance;
  }

  void _handleTelemetryEvent(TelemetryEvent event) {
    if (event.voltage != null) {
      if (event.voltage! >= 13.0 && _currentTrip == null) {
        startTrip();
      } else if (event.voltage! < 12.7 && _currentTrip != null) {
        endTrip();
      }
    }
    if (_currentTrip != null) {
      if (event.vehicle != null) {
        updateTripVehicle(Vehicle.fromVin(event.vehicle!.vin));
      }
      if (event.mileage != null) {
        updateTripMileage(event.mileage);
      }
    }
  }

  Future<void> startTrip() async {
    if (_currentTrip != null) {
      CustomLogger.e("Trip already started");
      return;
    }
    _instance._prefs.reload();
    CustomLogger.d("in startTrip");
    // get position
    TripLocation? currentLocation =
        await GpsService().getLocationFromCurrentPosition();
    try {
      CustomLogger.d("in try block");
      _currentTrip = Trip(
        tripCategory: TripCategory
            .values[_instance._prefs.getInt('tripCategory2') ?? 0]
            .toString(),
        tripStatus: TripStatus.inProgress.toString(),
        startLocationJson: currentLocation == null
            ? null
            : jsonEncode(currentLocation.toJson()),
      );
    } catch (e) {
      CustomLogger.e('Error while starting trip: $e');
    }
    CustomLogger.d("Trip start");
    CustomLogger.i('Trip started: ${jsonEncode(_currentTrip!.toJson())}');
  }

  void updateTripMileage(int? mileage) {
    if (mileage == null) {
      CustomLogger.e("Received Mileage is null, cannot update trip");
      return;
    }
    _currentMileage = mileage;
    if (_currentTrip!.startMileage == null) {
      _currentTrip!.startMileage = _currentMileage;
    }
    CustomLogger.i('Added start mileage to trip: $mileage');
  }

  void updateTripVehicle(Vehicle? vehicle) {
    if (vehicle == null) {
      CustomLogger.e("Vehicle is null, cannot update trip");
      return;
    }
    _currentTrip!.vehicleJson = jsonEncode(vehicle.toJson());
    CustomLogger.i('Added Vehicle to trip: ${jsonEncode(vehicle.toJson())}');
  }

  Future<void> endTrip() async {
    if (_currentTrip == null) {
      CustomLogger.e("Trip not found");
    }
    try {
      TripLocation? endLocation =
          await GpsService().getLocationFromCurrentPosition();
      _currentTrip!.endLocationJson =
          endLocation == null ? null : jsonEncode(endLocation.toJson());
      _currentTrip!.endMileage = _currentMileage;
      _currentTrip!.endTimestamp = DateTime.now().toIso8601String();
      final status = _currentTrip!.isTripCorrect()
          ? TripStatus.completed
          : TripStatus.incorrect;
      _currentTrip!.tripStatus = status.toString();
      CustomLogger.i('Trip ended: ${jsonEncode(_currentTrip!.toJson())}');
      TripRepository.saveTrip(_currentTrip!);
    } catch (e) {
      CustomLogger.e('Error while ending trip: $e');
    }
    _currentTrip = null;
  }

  void dispose() {
    _subscription.cancel();
  }
}
