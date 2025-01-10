// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:objectbox/objectbox.dart';

import './location.dart';
import './trip_category.dart';
import './trip_status.dart';

@Entity()
class Trip {
  @Id()
  int id = 0;

  final ToOne<Location> startLocation = ToOne<Location>();
  final ToOne<Location> endLocation = ToOne<Location>();

  final int startMileage;
  final int? endMileage;
  final int currentMileage;
  final String vin;
  final String startTimestamp;
  final String tripCategory;
  final String? endTimestamp;
  final String tripStatus;

  Trip({
    required ToOne<Location> startLocation,
    required this.startMileage,
    required this.vin,
    this.endTimestamp,
    this.endMileage,
    String? status,
    String? category,
  })  : tripCategory = category ?? TripCategory.business.toString(),
        startTimestamp = DateTime.now().toIso8601String(),
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
    ToOne<Location>? startLocation,
    ToOne<Location>? endLocation,
  }) {
    return Trip(
      startMileage: startMileage ?? this.startMileage,
      endMileage: endMileage ?? this.endMileage,
      vin: vin ?? this.vin,
      category: tripCategory ?? this.tripCategory,
      startLocation: startLocation ?? this.startLocation,
      endTimestamp: endTimestamp ?? this.endTimestamp,
    )..endLocation.target = endLocation?.target;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'startMileage': startMileage,
      'endMileage': endMileage,
      'vin': vin,
      'startTimestamp': startTimestamp,
      'endTimestamp': endTimestamp,
      'tripCategory': tripCategory,
      'tripStatus': tripStatus,
    };
  }

//   factory Trip.fromMap(Map<String, dynamic> map) {
//     return Trip(
//       id: map['id'] as int,
//       startMileage: map['startMileage'] as int,
//       endMileage: map['endMileage'] != null ? map['endMileage'] as int : null,
//       vin: map['vin'] as String,
//       startTimestamp: map['startTimestamp'] as String,
//       endTimestamp:
//           map['endTimestamp'] != null ? map['endTimestamp'] as String : null,
//       tripCategory: map['tripCategory'] as String,
//       tripStatus: map['tripStatus'] as String,
//     );
//   }

//   String toJson() => json.encode(toMap());

//   factory Trip.fromJson(String source) =>
//       Trip.fromMap(json.decode(source) as Map<String, dynamic>);

//   @override
//   String toString() {
//     return 'Trip(id: $id, startMileage: $startMileage, endMileage: $endMileage, vin: $vin, startTimestamp: $startTimestamp, endTimestamp: $endTimestamp, tripCategory: $tripCategory, tripStatus: $tripStatus)';
//   }

//   @override
//   bool operator ==(covariant Trip other) {
//     if (identical(this, other)) return true;

//     return other.id == id &&
//         other.startMileage == startMileage &&
//         other.endMileage == endMileage &&
//         other.vin == vin &&
//         other.startTimestamp == startTimestamp &&
//         other.endTimestamp == endTimestamp &&
//         other.tripCategory == tripCategory &&
//         other.tripStatus == tripStatus;
//   }

//   @override
//   int get hashCode {
//     return id.hashCode ^
//         startMileage.hashCode ^
//         endMileage.hashCode ^
//         vin.hashCode ^
//         startTimestamp.hashCode ^
//         endTimestamp.hashCode ^
//         tripCategory.hashCode ^
//         tripStatus.hashCode;
//   }
}
