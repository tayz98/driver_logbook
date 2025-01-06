import './location.dart';
import './trip_information.dart';
import './trip_status.dart';
import './trip_category.dart';
import './telemetry.dart';
import "package:flutter_riverpod/flutter_riverpod.dart";

class Trip {
  final int id;
  final int driverId;
  TripInformation tripInformation = TripInformation();
  Location startLocation;
  Location? endLocation;
  double startMileage;
  double? endMileage;
  TripCategory tripCategory;
  TripStatus tripStatus = TripStatus.inProgress;
  Telemetry? telemetry;

  Trip({
    required this.driverId,
    required this.startLocation,
    this.endLocation,
    required this.tripStatus,
    required this.startMileage,
    this.endMileage,
    required this.tripCategory,
  }) : id = DateTime.now().millisecondsSinceEpoch;
}

class TripNotifier extends StateNotifier<Trip?> {
  TripNotifier(super.state);

  void startTrip(Trip trip) {
    state = Trip(
        driverId: trip.driverId,
        startLocation: trip.startLocation,
        startMileage: trip.startMileage,
        tripCategory: trip.tripCategory,
        tripStatus: TripStatus.inProgress);
  }

  void endTrip() {
    if (state != null) {
      state!.tripStatus = TripStatus.finished;
      state!.endMileage = state!.startMileage;
      state!.endLocation = state!.startLocation;
    }
  }

  void cancelTrip() {
    if (state != null) {
      state!.tripStatus = TripStatus.cancelled;
      // TODO: think about it
    }
  }

  void updateTrip(Trip trip) {
    state = trip;
  }
}
