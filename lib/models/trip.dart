import 'package:objectbox/objectbox.dart';

import './location.dart';
import './trip_information.dart';
import './trip_status.dart';
import './trip_category.dart';

@Entity()
class Trip {
  @Id()
  int id = 0;

  final tripInformation = ToOne<TripInformation>();
  final startLocation = ToOne<Location>();
  final endLocation = ToOne<Location?>();

  int startMileage;
  int? endMileage;
  String tripCategory;
  String tripStatus;
  String vin;
  String startTimestamp = DateTime.now().toIso8601String();
  String? endTimestamp;

  Trip({
    required ToOne<Location> startLocation,
    required this.tripStatus,
    required this.startMileage,
    required this.tripCategory,
    required this.vin,
  });

  TripCategory get tripCategoryEnum =>
      TripCategory.values.firstWhere((e) => e.toString() == tripCategory);

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);
}
