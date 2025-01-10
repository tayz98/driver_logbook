import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox/objectbox.dart';
import '../models/trip.dart';
import '../models/trip_location.dart';
import '../models/trip_status.dart';

// TODO: combine with objectBox store
class TripNotifier extends StateNotifier<Trip> {
  TripNotifier()
      : super(
          Trip(
            startMileage: 0,
            vin: '',
            startLocation: ToOne<TripLocation>()
              ..target = TripLocation(
                city: '',
                postalCode: '',
                street: '',
              ),
            endLocation: ToOne<TripLocation>()..target = null,
            endMileage: null,
            endTimestamp: null,
          ),
        );

  void initializeTrip({
    required int startMileage,
    required String vin,
    required TripLocation startLocation,
  }) {
    state = Trip(
      startMileage: startMileage,
      vin: vin,
      startLocation: ToOne<TripLocation>()..target = startLocation,
      endLocation: ToOne<TripLocation>()..target = null,
      endMileage: null,
      endTimestamp: null,
      status: TripStatus.inProgress.toString(),
    );
  }

  void updateMileage(int mileage) {
    state = state.copyWith(currentMileage: mileage);
  }

  void setEndLocation(TripLocation location) {
    state = state.copyWith(
      endLocation: ToOne<TripLocation>()..target = location,
    );
  }

  void endTrip() {
    if (!isTripInProgress) {
      throw Exception('Trip is not in progress');
    }
    state = state.copyWith(
      endMileage: state.currentMileage,
      endTimestamp: DateTime.now().toIso8601String(),
      endLocation: state.endLocation,
      tripStatus: TripStatus.finished.toString(),
    );
  }

  void cancelTrip() {
    state = state.copyWith(
      endMileage: state.startMileage,
      tripStatus: TripStatus.cancelled.toString(),
    );
  }

  bool get isTripInProgress => state.tripStatusEnum == TripStatus.inProgress;
  bool get isTripNotStarted => state.tripStatusEnum == TripStatus.notStarted;
  Trip get trip => state;
}
