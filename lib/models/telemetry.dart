// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:objectbox/objectbox.dart';

import 'gps.dart';
import 'vehicle_diagnostics.dart';

@Entity()
class Telemetry {
  @Id()
  int id = 0;
  final StreamController<Telemetry> _controller =
      StreamController<Telemetry>.broadcast();
  Stream<Telemetry> get stream => _controller.stream;
  final gps = ToOne<Gps>();
  final vehicleDiagnostics = ToOne<VehicleDiagnostics>();
  Telemetry({
    required ToOne<Gps> gps,
    required ToOne<VehicleDiagnostics> vehicleDiagnostics,
    required this.id,
  });

  void dispose() {
    _controller.close();
  }

  void updateVehicleDiagnostics(VehicleDiagnostics diagnostics) {
    vehicleDiagnostics.target = diagnostics;
    _controller.add(this);
  }

  void updateGps(Gps gpsData) {
    gps.target = gpsData;
    _controller.add(this);
  }

  Telemetry copyWith({
    int? id,
  }) {
    return Telemetry(
      id: id ?? this.id,
      gps: gps,
      vehicleDiagnostics: vehicleDiagnostics,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
    };
  }

  factory Telemetry.fromMap(Map<String, dynamic> map) {
    return Telemetry(
      id: map['id'] as int,
      gps: ToOne<Gps>(),
      vehicleDiagnostics: ToOne<VehicleDiagnostics>(),
    );
  }

  String toJson() => json.encode(toMap());

  factory Telemetry.fromJson(String source) =>
      Telemetry.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'Telemetry(id: $id)';

  @override
  bool operator ==(covariant Telemetry other) {
    if (identical(this, other)) return true;

    return other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
