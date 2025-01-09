import 'package:objectbox/objectbox.dart';

import './location.dart';
import './trip_information.dart';
import './trip_status.dart';
import './trip_category.dart';
import './telemetry.dart';

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
  final telemetry = ToOne<Telemetry>();

  Trip({
    required ToOne<Location> startLocation,
    required ToOne<Telemetry> telemetry,
    required this.tripStatus,
    required this.startMileage,
    required this.tripCategory,
  });

  TripCategory get tripCategoryEnum =>
      TripCategory.values.firstWhere((e) => e.toString() == tripCategory);

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);
}
