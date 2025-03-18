import 'package:driver_logbook/models/vehicle.dart';

class TelemetryEvent {
  final double? voltage;
  final Vehicle? vehicle;
  final int? mileage;

  TelemetryEvent({
    this.voltage,
    this.vehicle,
    this.mileage,
  });

  @override
  String toString() {
    return 'TelemetryEvent(voltage: $voltage, vehicle: ${vehicle?.toString() ?? 'null'}, mileage: $mileage)';
  }
}
