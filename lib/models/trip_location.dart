import 'package:objectbox/objectbox.dart';

@Entity()
class TripLocation {
  @Id()
  int id = 0;
  final String street;
  final String city;
  final String postalCode;

  TripLocation({
    required this.street,
    required this.city,
    required this.postalCode,
  });

  @override
  String toString() {
    return 'TripLocation{street: $street, city: $city, postalCode: $postalCode}';
  }
}
