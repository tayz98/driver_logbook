class Vehiclediagnostics {
  final String vin;
  double currentMileage;
  DateTime? lastMileageUpdate;

  Vehiclediagnostics(
      {required this.vin,
      required this.currentMileage,
      this.lastMileageUpdate});
}
