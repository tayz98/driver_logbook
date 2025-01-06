import '../models/trip.dart';
import '../models/trip_status.dart';
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

  // Get trips by status
  List<Trip> getTripsByStatus(TripStatus status) {
    return _tripBox
        .query(Trip_.tripStatus.equals(status.index as String))
        .build()
        .find();
  }
}
