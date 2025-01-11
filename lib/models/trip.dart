// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:objectbox/objectbox.dart';
import 'trip_location.dart';
import './trip_category.dart';
import './trip_status.dart';

@Entity()
class Trip {
  @Id()
  int id = 0;

  final ToOne<TripLocation> startLocation;
  final ToOne<TripLocation> endLocation;

  final int startMileage;
  final int? endMileage;
  final int? currentMileage;
  final String vin;
  final String startTimestamp;
  final String tripCategory;
  final String? endTimestamp;
  final String tripStatus;

  Trip(
      {required this.startLocation,
      required this.endLocation,
      required this.startMileage,
      required this.vin,
      required this.startTimestamp,
      required this.endTimestamp,
      required this.endMileage,
      required this.currentMileage,
      required this.tripStatus,
      required this.tripCategory});

  TripCategory get tripCategoryEnum {
    return TripCategory.values.firstWhere((e) => e.toString() == tripCategory);
  }

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);

  @override
  String toString() {
    return 'Trip{id: $id, startMileage: $startMileage, currentMileage: $currentMileage, endMileage: $endMileage, vin: $vin, startTimestamp: $startTimestamp, endTimestamp: $endTimestamp, tripCategory: $tripCategory, tripStatus: $tripStatus, startLocation: $startLocation, endLocation: $endLocation}';
  }

  Trip copyWith({
    int? startMileage,
    int? currentMileage,
    int? endMileage,
    String? vin,
    String? startTimestamp,
    String? endTimestamp,
    String? tripCategory,
    String? tripStatus,
    ToOne<TripLocation>? startLocation,
    ToOne<TripLocation>? endLocation,
  }) {
    return Trip(
      startMileage: startMileage ?? this.startMileage,
      currentMileage: currentMileage ?? this.currentMileage,
      endMileage: endMileage ?? this.endMileage,
      vin: vin ?? this.vin,
      startTimestamp: startTimestamp ?? this.startTimestamp,
      tripCategory: tripCategory ?? this.tripCategory,
      tripStatus: tripStatus ?? this.tripStatus,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      endTimestamp: endTimestamp ?? this.endTimestamp,
    );
  }
}
