import 'package:objectbox/objectbox.dart';

@Entity()
class Gps {
  int id = 0;
  String? _latitude;
  Gps();
  // TODO: think about what properties you need for GPS data
}
