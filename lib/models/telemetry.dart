import 'package:objectbox/objectbox.dart';

import 'gps.dart';
import 'vehicle_diagnostics.dart';

@Entity()
class Telemetry {
  @Id()
  int id = 0;
  final gps = ToOne<Gps>();
  final vehicleDiagnostics = ToOne<Vehiclediagnostics>();
  Telemetry({
    required ToOne<Gps> gps,
    required ToOne<Vehiclediagnostics> vehicleDiagnostics,
  });
}
