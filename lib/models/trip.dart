import 'dart:convert';

import 'package:elogbook/models/driver.dart';
import 'package:objectbox/objectbox.dart';
import 'trip_location.dart';
import './trip_category.dart';
import './trip_status.dart';

@Entity()
class Trip {
  @Id()
  int id = 0;
  // final TripLocation startLocation;
  // TripLocation? endLocation;
  String startLocationJson;
  String? endLocationJson;
  final ToOne<Driver> driver;

  final int startMileage;
  final String vin;
  final String startTimestamp;
  String? endTimestamp;
  int? endMileage;
  String tripCategory;
  String tripStatus;

  Trip({
    required this.startMileage,
    required this.driver,
    required this.vin,
    required this.tripCategory,
    required this.tripStatus,
    required this.startLocationJson,
    this.endLocationJson,
    this.endMileage,
    this.endTimestamp,
  }) : startTimestamp = DateTime.now().toIso8601String();

  TripCategory get tripCategoryEnum {
    return TripCategory.values.firstWhere((e) => e.toString() == tripCategory);
  }

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);

  // Getter/Setter for startLocation
  TripLocation get startLocation {
    if (startLocationJson.isEmpty) {
      throw const FormatException("startLocationJson is empty");
    }
    return TripLocation.fromJson(jsonDecode(startLocationJson));
  }

  set startLocation(TripLocation location) =>
      startLocationJson = jsonEncode(location.toJson());

  // Getter/Setter for endLocation
  TripLocation? get endLocation => endLocationJson != null
      ? TripLocation.fromJson(jsonDecode(endLocationJson!))
      : null;
  set endLocation(TripLocation? location) =>
      endLocationJson = location != null ? jsonEncode(location.toJson()) : null;

  String getCategoryShortForm(String category) {
    return category.split('.').last;
  }

  String getStatusShortForm(String status) {
    return status.split('.').last;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driver.target?.uid,
      'driverName': driver.target?.lastName,
      'startMileage': startMileage,
      'endMileage': endMileage,
      'vin': vin,
      'startTimestamp': startTimestamp,
      'endDate': endTimestamp,
      'tripCategory': getCategoryShortForm(tripCategory),
      'tripStatus': getStatusShortForm(tripStatus),
      'startLocation': startLocation.toJson(),
      'endLocation': endLocation?.toJson(),
    };
  }

  @override
  String toString() {
    return '''
Trip {
  id: $id,
  driverId: ${driver.target?.uid},
  driverName: ${driver.target?.lastName},
  startMileage: $startMileage,
  endMileage: $endMileage,
  vin: $vin,
  startTimestamp: $startTimestamp,
  endTimestamp: $endTimestamp,
  tripCategory: $tripCategory,
  tripStatus: $tripStatus,
  startLocation: ${startLocation.toString()},
  endLocation: ${endLocation.toString()},
}
''';
  }
}
