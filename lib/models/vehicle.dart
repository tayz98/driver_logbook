import 'package:rebi_vin_decoder/rebi_vin_decoder.dart';

class Vehicle {
  final String vin;
  final String manufacturer;
  final int year;
  final String region;
  // model or make not possible right now
  // because either a big database or a fee-based API is needed

  Vehicle({
    required this.vin,
    required this.manufacturer,
    required this.year,
    required this.region,
  });

  factory Vehicle.fromVin(String vin) {
    final decodedVin = VIN(number: vin);

    return Vehicle(
        vin: vin,
        manufacturer: decodedVin.getManufacturer() ?? 'Unknown Manufacturer',
        year: decodedVin.getYear() ?? 0,
        region: decodedVin.getRegion());
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      vin: json['vin'],
      manufacturer: json['manufacturer'],
      year: json['year'],
      region: json['region'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vin': vin,
      'manufacturer': manufacturer,
      'year': year,
      'region': region,
    };
  }

  @override
  String toString() {
    return 'Vehicle{vin: $vin, manufacturer: $manufacturer, year: $year, region: $region}';
  }
}
