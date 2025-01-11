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
  final int currentMileage;
  final String vin;
  final String startTimestamp;
  final String tripCategory;
  final String? endTimestamp;
  final String tripStatus;

  Trip({
    required this.startLocation,
    required this.endLocation,
    required this.startMileage,
    required this.vin,
    required this.startTimestamp,
    this.endTimestamp,
    this.endMileage,
    String? status,
    String? category,
  })  : tripCategory = category ?? TripCategory.business.toString(),
        currentMileage = startMileage,
        tripStatus = status ?? TripStatus.notStarted.toString();

  TripCategory get tripCategoryEnum =>
      TripCategory.values.firstWhere((e) => e.toString() == tripCategory);

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);

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
      endMileage: endMileage ?? this.endMileage,
      vin: vin ?? this.vin,
      startTimestamp: startTimestamp ?? this.startTimestamp,
      category: tripCategory ?? this.tripCategory,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      endTimestamp: endTimestamp ?? this.endTimestamp,
    );
  }
}
