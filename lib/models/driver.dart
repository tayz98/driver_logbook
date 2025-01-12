import 'package:elogbook/models/trip.dart';
import 'package:objectbox/objectbox.dart';
import 'package:uuid/uuid.dart';

@Entity()
class Driver {
  @Id()
  int id = 0;
  //bool isAuthorized = false;
  final bool isAllowedToDoPrivateTrips;
  final String name;
  final String surname;

  @Index()
  @Unique()
  String uid;

  @Backlink()
  final trips = ToMany<Trip>();

  Driver(
      {required this.name,
      required this.surname,
      required this.isAllowedToDoPrivateTrips})
      : uid = const Uuid().v4();

  @override
  String toString() {
    return 'Driver{id: $id, name: $name, surname: $surname, isAllowedToDoPrivateTrips: $isAllowedToDoPrivateTrips, uid: $uid}';
  }

  Driver copyWith({
    bool? isAllowedToDoPrivateTrips,
    String? name,
    String? surname,
  }) {
    return Driver(
      isAllowedToDoPrivateTrips:
          isAllowedToDoPrivateTrips ?? this.isAllowedToDoPrivateTrips,
      name: name ?? this.name,
      surname: surname ?? this.surname,
    );
  }
}
