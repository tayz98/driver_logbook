import 'package:driver_logbook/models/trip_status.dart';
import 'package:driver_logbook/objectbox.dart';

import '../models/trip.dart';
import '../objectbox.g.dart';

class TripRepository {
  // Get all trips
  static List<Trip> getAllTrips() {
    return ObjectBox.store.box<Trip>().getAll();
  }

  // Get a trip by ID
  static Trip? getTripById(int id) {
    return ObjectBox.store.box<Trip>().get(id);
  }

  // Save a trip
  static void saveTrip(Trip trip) {
    ObjectBox.store.box<Trip>().put(trip);
  }

  // Delete a trip
  static void deleteTrip(int id) {
    ObjectBox.store.box<Trip>().remove(id);
  }

  // return all finished trips
  static List<Trip> getFinishedTrips() {
    return ObjectBox.store
        .box<Trip>()
        .query(Trip_.tripStatus.equals(TripStatus.completed.toString()))
        .build()
        .find();
  }

  // return all cancelled trips
  static List<Trip> getCancelledTrips() {
    return ObjectBox.store
        .box<Trip>()
        .query(Trip_.tripStatus.equals(TripStatus.incorrect.toString()))
        .build()
        .find();
  }

  // return cancelled and finished trips
  static List<Trip> getFinishedAndCancelledTrips() {
    return ObjectBox.store
        .box<Trip>()
        .query(Trip_.tripStatus
            .equals(TripStatus.incorrect.toString())
            .or(Trip_.tripStatus.equals(TripStatus.completed.toString())))
        .build()
        .find();
  }
}
