import 'dart:async';
import 'dart:convert';

import 'package:driver_logbook/models/globals.dart';
import 'package:driver_logbook/models/telemetry_bus.dart';
import 'package:driver_logbook/models/telemetry_event.dart';
import 'package:driver_logbook/models/trip.dart';
import 'package:driver_logbook/models/trip_category.dart';
import 'package:driver_logbook/models/trip_location.dart';
import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/models/vehicle.dart';
import 'package:driver_logbook/notification_configuration.dart';
import 'package:driver_logbook/repositories/trip_repository.dart';
import 'package:driver_logbook/services/gps_service.dart';
import 'package:driver_logbook/utils/custom_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TripState { idle, starting, inProgress, ending }

TripState _tripState = TripState.idle;

class TripController {
  // Singleton
  TripController._internal();
  Trip? _currentTrip;
  Trip? get currentTrip => _currentTrip;
  int? _currentMileage;
  bool get isTripInProgress => _currentTrip != null;
  late final SharedPreferences _prefs;
  late final StreamSubscription<TelemetryEvent> _subscription;
  Timer? _tripActivityTimer;
  DateTime? _lastTelemetryEventTime;
  static const int _tripInactivityTimeoutSeconds = 15;

  static final TripController _instance = TripController._internal();
  factory TripController() => _instance;
  static Future<TripController> initialize() async {
    _instance._prefs = await SharedPreferences.getInstance();
    _instance._subscription =
        TelemetryBus().stream.listen(_instance._handleTelemetryEvent);

    return _instance;
  }

  void _checkTripActivity() {
    if (_currentTrip == null || _lastTelemetryEventTime == null) {
      _tripActivityTimer?.cancel();
      _tripActivityTimer = null;
      return;
    }

    final now = DateTime.now();
    final difference = now.difference(_lastTelemetryEventTime!).inSeconds;

    CustomLogger.d("Time since last telemetry event: $difference seconds");

    if (difference > _tripInactivityTimeoutSeconds) {
      CustomLogger.w(
          "No telemetry events received for $_tripInactivityTimeoutSeconds seconds, ending trip");
      _endTrip();
      _tripActivityTimer?.cancel();
      _tripActivityTimer = null;
    }
  }

  void _startOrResetInactivityTimer() {
    // Cancel existing timer if it exists
    _tripActivityTimer?.cancel();

    // Only start the timer if a trip is in progress
    if (_currentTrip != null) {
      _tripActivityTimer = Timer.periodic(
          const Duration(seconds: 30), // Check every 30 seconds
          (timer) => _checkTripActivity());
      CustomLogger.d("Trip inactivity timer started/reset");
    }
  }

  void _handleTelemetryEvent(TelemetryEvent event) {
    _lastTelemetryEventTime = DateTime.now();
    _startOrResetInactivityTimer();
    if (event.voltage != null) {
      if (event.voltage! >= 13.0 && _currentTrip == null) {
        _startTrip();
      } else if (event.voltage! < 12.8 && _currentTrip != null) {
        _endTrip();
      }
    }
    if (_currentTrip != null) {
      if (event.vehicle != null) {
        _updateTripVehicle(Vehicle.fromVin(event.vehicle!.vin));
      }
      if (event.mileage != null && event.mileage! > 0) {
        _updateTripMileage(event.mileage);
      }
    }
  }

  Future<void> _startTrip() async {
    if (_currentTrip != null || _tripState != TripState.idle) {
      CustomLogger.e("Trip already started");
      return;
    }
        showBasicNotification(title: "Fahrt gestartet", body: "Fahrt gestartet");
    _tripState = TripState.starting;
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
      _tripState = TripState.inProgress;
      _lastTelemetryEventTime = DateTime.now();
      _startOrResetInactivityTimer();
    } catch (e) {
      _tripState = TripState.idle;
      CustomLogger.e('Error while starting trip: $e');
      showBasicNotification(
          title: "Fehler beim Starten der Fahrt!",
          body: "Fehler beim Starten der Fahrt!");
    }
    CustomLogger.d("Trip start");
    CustomLogger.i('Trip started: ${jsonEncode(_currentTrip!.toJson())}');
  }

  void _updateTripMileage(int? mileage) {
    if (mileage == null || _currentTrip == null) {
      CustomLogger.e(
          "Received Mileage is null or no trip in progress, cannot update trip");
      return;
    }

    _currentMileage = mileage;
    if (_currentTrip!.startMileage == null) {
      _currentTrip = _currentTrip!.copyWith(startMileage: _currentMileage);
      CustomLogger.i('Added start mileage to trip: $mileage');
    }
  }

  void _updateTripVehicle(Vehicle? vehicle) {
    if (vehicle == null || _currentTrip == null) {
      CustomLogger.e(
          "Vehicle is null or no trip in progress, cannot update trip");
      return;
    }

    _currentTrip = _currentTrip!.withVehicle(vehicle);
    CustomLogger.i('Added Vehicle to trip: ${jsonEncode(vehicle.toJson())}');
  }

  Future<void> _endTrip() async {
    showBasicNotification(title: "Fahrt beendet", body: "Fahrt beendet");
    if (_currentTrip == null || _tripState != TripState.inProgress) {
      CustomLogger.e("Trip not found");
      return;
    }
    _tripState = TripState.ending;
    _tripActivityTimer?.cancel();
    _tripActivityTimer = null;
    try {
      TripLocation? endLocation =
          await GpsService().getLocationFromCurrentPosition();
      // Create updated trip with all the end trip data
      final updatedTrip = _currentTrip!.copyWith(
        endMileage: _currentMileage,
        endTimestamp: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      // Add end location if available
      final tripWithLocation = endLocation != null
          ? updatedTrip.withEndLocation(endLocation)
          : updatedTrip;

      // Set the final trip status
      final status = tripWithLocation.isTripCorrect()
          ? TripStatus.completed
          : TripStatus.incorrect;

      final finalTrip =
          tripWithLocation.copyWith(tripStatus: status.toString());

      CustomLogger.i('Trip ended: ${jsonEncode(finalTrip.toJson())}');
      TripRepository.saveTrip(finalTrip);
      _currentTrip = null;
      syncTrips();
    } catch (e) {
      CustomLogger.e('Error while ending trip: $e');
      showBasicNotification(
          title: "Fehler beim Beenden der Fahrt!",
          body: "Fehler beim Beenden der Fahrt!");
    } finally {
      _tripState = TripState.idle;
    }
  }

  void dispose() {
    _subscription.cancel();
  }
}
