import 'package:objectbox/objectbox.dart';

@Entity()
class Vehiclediagnostics {
  @Id()
  int id = 0;
  final String vin;
  double currentMileage;

  Vehiclediagnostics({
    required this.vin,
    required this.currentMileage,
  });
}
