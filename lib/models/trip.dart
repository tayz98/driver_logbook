import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'trip_location.dart';
import './trip_category.dart';
import './trip_status.dart';
import './vehicle.dart';

@Entity()
class Trip {
  @Id()
  int id;

  final String? startLocationJson;
  final String? endLocationJson;
  final String? vehicleJson;
  final int? startMileage;
  final String? endTimestamp;
  final int? endMileage;
  final String tripCategory;
  final String tripStatus;
  final String startTimestamp;

  Trip({
    this.id = 0,
    this.startMileage,
    this.vehicleJson,
    this.startLocationJson,
    this.endLocationJson,
    this.endMileage,
    this.endTimestamp,
    required this.tripStatus,
    required this.tripCategory,
    String? startTimestamp,
  }) : startTimestamp =
            startTimestamp ?? DateTime.now().millisecondsSinceEpoch.toString();

  // Create a copy of this Trip with optional new values
  Trip copyWith({
    int? id,
    String? startLocationJson,
    String? endLocationJson,
    String? vehicleJson,
    int? startMileage,
    String? endTimestamp,
    int? endMileage,
    String? tripCategory,
    String? tripStatus,
    String? startTimestamp,
  }) {
    return Trip(
      id: id ?? this.id,
      startLocationJson: startLocationJson ?? this.startLocationJson,
      endLocationJson: endLocationJson ?? this.endLocationJson,
      vehicleJson: vehicleJson ?? this.vehicleJson,
      startMileage: startMileage ?? this.startMileage,
      endTimestamp: endTimestamp ?? this.endTimestamp,
      endMileage: endMileage ?? this.endMileage,
      tripCategory: tripCategory ?? this.tripCategory,
      tripStatus: tripStatus ?? this.tripStatus,
      startTimestamp: startTimestamp ?? this.startTimestamp,
    );
  }

  TripCategory get tripCategoryEnum {
    return TripCategory.values.firstWhere((e) => e.toString() == tripCategory);
  }

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);

  // Getter/Setter for startLocation
  TripLocation? get startLocation {
    if (startLocationJson == null ||
        startLocationJson!.isEmpty ||
        startLocationJson == "null") {
      return null;
    }
    return TripLocation.fromJson(jsonDecode(startLocationJson!));
  }

  bool isTripCorrect() {
    // if a trip is business, it must have start and end mileage, start and end location and vehicle
    if (tripCategoryEnum == TripCategory.business) {
      return startMileage != null &&
          endMileage != null &&
          startLocationJson != null &&
          endLocationJson != null &&
          vehicleJson != null;
    }
    // if a trip is private, it must have start and end mileage and vehicle
    if (tripCategoryEnum == TripCategory.private ||
        tripCategoryEnum == TripCategory.commute) {
      return startMileage != null && endMileage != null && vehicleJson != null;
    }
    return false;
  }

  // Create a new Trip with updated startLocation
  Trip withStartLocation(TripLocation? location) {
    return copyWith(
      startLocationJson:
          location != null ? jsonEncode(location.toJson()) : null,
    );
  }

  // Create a new Trip with updated vehicle
  Trip withVehicle(Vehicle? vehicle) {
    return copyWith(
      vehicleJson: vehicle != null ? jsonEncode(vehicle.toJson()) : null,
    );
  }

  Vehicle? get vehicle {
    if (vehicleJson == null || vehicleJson == "null") {
      return null;
    }
    return Vehicle.fromJson(jsonDecode(vehicleJson!));
  }

  // Getter for endLocation
  TripLocation? get endLocation => endLocationJson != null
      ? TripLocation.fromJson(jsonDecode(endLocationJson!))
      : null;

  // Create a new Trip with updated endLocation
  Trip withEndLocation(TripLocation? location) {
    return copyWith(
      endLocationJson: location != null ? jsonEncode(location.toJson()) : null,
    );
  }

  String getCategoryShortForm(String category) {
    return category.split('.').last;
  }

  String getStatusShortForm(String status) {
    return status.split('.').last;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startMileage': startMileage,
      'endMileage': endMileage,
      'vehicle': vehicle?.toJson(),
      'startTimestamp': startTimestamp,
      'endTimestamp': endTimestamp,
      'tripCategory': getCategoryShortForm(tripCategory),
      'tripStatus': getStatusShortForm(tripStatus),
      'startLocation': startLocation?.toJson(),
      'endLocation': endLocation?.toJson(),
    };
  }

  static Trip fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] ?? 0,
      startMileage: json['startMileage'],
      endMileage: json['endMileage'],
      vehicleJson: json['vehicle'] != null ? jsonEncode(json['vehicle']) : null,
      startLocationJson: json['startLocation'] != null
          ? jsonEncode(json['startLocation'])
          : null,
      endLocationJson:
          json['endLocation'] != null ? jsonEncode(json['endLocation']) : null,
      endTimestamp: json['endTimestamp'],
      tripStatus: json['tripStatus'],
      tripCategory: json['tripCategory'],
      startTimestamp: json['startTimestamp'],
    );
  }

  @override
  String toString() {
    return '''
Trip {
  id: $id,
  startMileage: $startMileage,
  endMileage: $endMileage,
  vehicle: ${vehicle.toString()},
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
