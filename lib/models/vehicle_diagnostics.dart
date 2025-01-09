import 'package:objectbox/objectbox.dart';

@Entity()
class VehicleDiagnostics {
  @Id()
  int id = 0;
  @Unique()
  final String vin;
  int currentMileage;

  VehicleDiagnostics({
    required this.vin,
    required this.currentMileage,
  });

  VehicleDiagnostics copyWith({
    String? vin,
    int? currentMileage,
  }) {
    return VehicleDiagnostics(
      vin: vin ?? this.vin,
      currentMileage: currentMileage ?? this.currentMileage,
    );
  }
}
