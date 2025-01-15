import 'package:elogbook/models/trip_status.dart';

import '../models/trip.dart';
import '../objectbox.g.dart';

class TripRepository {
  final Box<Trip> _tripBox;

  TripRepository(Store store) : _tripBox = store.box<Trip>();

  // Get all trips
  List<Trip> getAllTrips() {
    return _tripBox.getAll();
  }

  // Get a trip by ID
  Trip? getTripById(int id) {
    return _tripBox.get(id);
  }

  // Save a trip
  void saveTrip(Trip trip) {
    _tripBox.put(trip);
  }

  // Delete a trip
  void deleteTrip(int id) {
    _tripBox.remove(id);
  }

  // return all finished trips
  // TODO: check functionality
  List<Trip> getFinishedTrips() {
    return _tripBox
        .query(Trip_.tripStatus.equals(TripStatus.finished.toString()))
        .build()
        .find();
  }
}
