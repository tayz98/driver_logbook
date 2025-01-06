import 'package:objectbox/objectbox.dart';

@Entity()
class Location {
  @Id()
  int id = 0;
  final String street;
  final String city;
  final String postalCode;

  Location({
    required this.street,
    required this.city,
    required this.postalCode,
  });
}
