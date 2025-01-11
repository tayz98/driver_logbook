import 'package:elogbook/models/trip_category.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox/objectbox.dart';
import '../models/trip.dart';
import '../models/trip_location.dart';
import '../models/trip_status.dart';

// TODO: combine with objectBox store
class TripNotifier extends StateNotifier<Trip> {
  final Ref ref; //  required for communicating with other providers
  TripNotifier(this.ref)
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
            currentMileage: 0,
            startTimestamp: "",
            endTimestamp: null,
            tripStatus: TripStatus.notStarted.toString(),
            tripCategory: TripCategory.business.toString(),
          ),
        );

  void initializeTrip({
    required int startMileage,
    required String vin,
    required TripLocation startLocation,
  }) {
    state = Trip(
      startMileage: startMileage,
      currentMileage: startMileage,
      vin: vin,
      startLocation: ToOne<TripLocation>()..target = startLocation,
      endLocation: ToOne<TripLocation>()..target = null,
      endMileage: null,
      startTimestamp: DateTime.now().toIso8601String(),
      endTimestamp: null,
      tripStatus: TripStatus.inProgress.toString(),
      tripCategory: TripCategory.business.toString(),
    );
  }

  void updateMileage(int mileage) {
    if (mileage <= state.currentMileage!) {
      return; // avoid setting same mileage
    }
    state = state.copyWith(currentMileage: mileage);
  }

  void setEndLocation(TripLocation location) {
    state = state.copyWith(
      endLocation: ToOne<TripLocation>()..target = location,
    );
  }

  void endTrip() {
    state = state.copyWith(
      endMileage: state.currentMileage,
      endTimestamp: DateTime.now().toIso8601String(),
      tripStatus: TripStatus.finished.toString(),
    );
  }

  void cancelTrip() {
    state = state.copyWith(
      endMileage: state.startMileage,
      tripStatus: TripStatus.cancelled.toString(),
    );
  }
}
