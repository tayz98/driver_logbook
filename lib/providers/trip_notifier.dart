import 'package:elogbook/models/trip_category.dart';
import 'package:elogbook/models/trip.dart';
import 'package:elogbook/models/trip_status.dart';
import 'package:elogbook/models/trip_location.dart';
import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    state = state.copyWith(
      startMileage: startMileage,
      currentMileage: startMileage,
      vin: vin,
      startLocation: ToOne<TripLocation>()..target = startLocation,
      startTimestamp: DateTime.now().toIso8601String(),
      tripStatus: TripStatus.inProgress.toString(),
    );
    // state = Trip(
    //   startMileage: startMileage,
    //   currentMileage: startMileage,
    //   vin: vin,
    //   startLocation: ToOne<TripLocation>()..target = startLocation,
    //   endLocation: ToOne<TripLocation>()..target = null,
    //   endMileage: null,
    //   startTimestamp: DateTime.now().toIso8601String(),
    //   endTimestamp: null,
    //   tripStatus: TripStatus.inProgress.toString(),
    //   tripCategory: TripCategory.business.toString(),
    // );
  }

  void changeMode(TripCategory mode) async {
    final modeString = mode.toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tripCategory', modeString);
    state = state.copyWith(tripCategory: modeString);
  }

  Future<void> restoreCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCategory =
        prefs.getString('tripCategory') ?? TripCategory.business.toString();
    state = state.copyWith(tripCategory: savedCategory);
    debugPrint('Saved trip category: ${state.toString()}');
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
