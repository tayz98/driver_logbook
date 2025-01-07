import 'package:objectbox/objectbox.dart';

@Entity()
class VehicleDiagnostics {
  @Id()
  int id = 0;
  @Unique()
  final String vin;
  double currentMileage;

  VehicleDiagnostics({
    required this.vin,
    required this.currentMileage,
  });

  VehicleDiagnostics copyWith({
    String? vin,
    double? currentMileage,
  }) {
    return VehicleDiagnostics(
      vin: vin ?? this.vin,
      currentMileage: currentMileage ?? this.currentMileage,
    );
  }
}
