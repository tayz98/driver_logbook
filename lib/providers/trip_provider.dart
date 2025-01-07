import 'dart:async';

import 'package:elogbook/models/location.dart';
import 'package:elogbook/models/telemetry.dart';
import 'package:elogbook/repositories/driver_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox/objectbox.dart';
import '../models/trip.dart';
import '../models/driver.dart';
import '../models/vehicle_diagnostics.dart';
import '../models/gps.dart';
import '../repositories/trip_repository.dart';
import '../services/elm327_services.dart';

class TripNotifier extends StateNotifier<Trip?> {
  final TripRepository _tripRepository;
  final DriverRepository _driverRepository;
  final Elm327Service? _elm327Service;
  Driver? currentDriver;
  StreamSubscription<VehicleDiagnostics>? _telemetrySubscription;
  StreamSubscription<bool>? _ignitionSubscription;
  StreamSubscription<void>? _telemetryStartedSubscription;

  TripNotifier(
      this._tripRepository, this._elm327Service, this._driverRepository)
      : super(null) {
    if (_elm327Service != null) {
      _startListening();
    }
  }

  void setDriver(Driver driver) {
    currentDriver = driver;
  }

  void startTrip() {
    if (currentDriver == null) {
      throw Exception("No driver is currently set.");
    }

    final newTrip = Trip(
      startLocation: ToOne<Location>(),
      telemetry: ToOne<Telemetry>(),
      tripStatus: "inProgress",
      startMileage: _elm327Service?.carMileage ?? 0,
      tripCategory: "business",
    );

    currentDriver!.trips.add(newTrip);
    state = newTrip;
    _driverRepository.saveDriver(currentDriver!);

    _telemetrySubscription =
        _elm327Service!.vehicleStream.listen((diagnostics) {
      updateVehicleData(diagnostics);
    });
  }

  void updateVehicleData(VehicleDiagnostics data) {
    if (state == null) {
      throw Exception("No trip is currently active.");
    }

    state!.telemetry.target?.updateVehicleDiagnostics(data);
    _tripRepository.saveTrip(state!);
  }

  void updateGpsData(Gps data) {
    if (state == null) {
      throw Exception("No trip is currently active.");
    }

    state!.telemetry.target?.updateGps(data);
    _tripRepository.saveTrip(state!);
  }

  void endTrip() {
    if (state == null) {
      throw Exception("No trip is currently active.");
    }

    state!.tripStatus = "finished";
    _tripRepository.saveTrip(state!);
    state = null;
    _telemetrySubscription?.cancel();
    _telemetrySubscription = null;
  }

  void _startTelemetryStartedListening() {
    // TODO: fix
    _telemetryStartedSubscription =
        _elm327Service!.telemetryStartedStream.listen((_) {
      _startListening();
    });
  }

  void _startListening() {
    _ignitionSubscription =
        _elm327Service!.ignitionStream.listen((isIgnitionOn) {
      if (isIgnitionOn && state == null) {
        startTrip();
      } else if (!isIgnitionOn && state != null) {
        endTrip();
      }
    });
  }

  @override
  void dispose() {
    _telemetrySubscription?.cancel();
    _ignitionSubscription?.cancel();
    _telemetryStartedSubscription?.cancel();
    super.dispose();
  }
}
