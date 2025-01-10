import 'package:elogbook/models/trip_category.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:objectbox/objectbox.dart';
import '../models/trip.dart';
import '../models/location.dart';
import '../models/trip_status.dart';

// TODO: combine with objectBox store
class TripNotifier extends StateNotifier<Trip> {
  TripNotifier()
      : super(
          Trip(
            startMileage: 0,
            vin: '',
            startLocation: ToOne<Location>(),
            endMileage: null,
            endTimestamp: null,
          ),
        );

  void initializeTrip({
    // TODO: get real location and add it here
    required int startMileage,
    required String vin,
  }) {
    state = Trip(
      startMileage: startMileage,
      vin: vin,
      startLocation: ToOne<Location>()
        ..target = Location(
            city: 'Muenchen',
            postalCode: '10115',
            street: 'Friedrichstraße 123'),
      endMileage: null,
      endTimestamp: null,
      status: TripStatus.inProgress.toString(),
    );
  }

  void updateMileage(int mileage) {
    state = state.copyWith(currentMileage: mileage);
  }

  void endTrip() {
    // get end location here
    state = state.copyWith(
      endMileage: state.currentMileage,
      endLocation: ToOne<Location>()
        ..target = Location(
            city: 'Berlin', postalCode: '10115', street: 'Friedrichstraße 123'),
      tripStatus: TripStatus.finished.toString(),
    );
  }

  void cancelTrip() {
    state = state.copyWith(
      endMileage: state.startMileage,
      endLocation: state.startLocation,
      tripStatus: TripStatus.cancelled.toString(),
    );
  }

  Trip get trip => state;

  bool get isTripInProgress => state.tripStatusEnum == TripStatus.inProgress;
}
