// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'trip.dart';
import 'package:objectbox/objectbox.dart';

@Entity()
class Driver {
  @Id(assignable: true)
  int id = 0;
  bool isAuthorized = false;
  bool privateTrips = false;
  final trips = ToMany<Trip>();

  Driver();
}
