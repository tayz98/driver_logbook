// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'trip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Driver {
  final int selfAssignedId;
  bool isAuthorized = false;
  bool privateTrips = false;
  Trip? currentTrip;

  Driver({
    required this.selfAssignedId,
  });
}

class DriverNotifier extends StateNotifier<Driver?> {
  DriverNotifier(super.state);

  void logIn(String id) {
    state = Driver(selfAssignedId: int.parse(id));
  }

  void logOut() {
    state = null;
  }

  void setDriver(Driver driver) {
    state = driver;
  }

  void setCurrentTrip(Trip trip) {
    if (state != null) {
      state!.currentTrip = trip;
    }
  }
}

final driverProvider = StateNotifierProvider<DriverNotifier, Driver?>((ref) {
  return DriverNotifier(null);
});
