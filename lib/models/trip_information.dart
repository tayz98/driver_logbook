import 'package:objectbox/objectbox.dart';

@Entity()
class TripInformation {
  @Id()
  int id = 0;
  final String _title = "Trip Service";
  String _description = "";
  TripInformation();
}
