import 'package:elogbook/models/trip.dart';
import 'package:objectbox/objectbox.dart';
import 'package:uuid/uuid.dart';

@Entity()
class Driver {
  @Id()
  int id = 0;
  //bool isAuthorized = false;
  bool isAllowedToDoPrivateTrips = false;
  final String name;
  final String surname;

  @Index()
  @Unique()
  String uid;

  @Backlink()
  final trips = ToMany<Trip>();

  Driver({required this.name, required this.surname}) : uid = const Uuid().v4();

  @override
  String toString() {
    return 'Driver{id: $id, name: $name, surname: $surname, isAllowedToDoPrivateTrips: $isAllowedToDoPrivateTrips, uid: $uid}';
  }
}
