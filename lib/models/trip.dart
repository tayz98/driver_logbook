import 'package:elogbook/models/driver.dart';
import 'package:objectbox/objectbox.dart';
import 'trip_location.dart';
import './trip_category.dart';
import './trip_status.dart';
import 'package:uuid/uuid.dart';

@Entity()
class Trip {
  @Id()
  int id = 0;

  final ToOne<TripLocation> startLocation = ToOne<TripLocation>();
  final ToOne<TripLocation> endLocation = ToOne<TripLocation>();
  final ToOne<Driver> driver;

  final int startMileage;
  final String vin;
  final String startTimestamp;
  @Index()
  @Unique()
  final String tripId;
  String? endTimestamp;
  int? endMileage;
  int currentMileage;
  String tripCategory;
  String tripStatus;

  Trip({
    required this.startMileage,
    required this.driver,
    required this.vin,
    required this.tripCategory,
    required this.tripStatus,
    this.endMileage,
    this.endTimestamp,
  })  : tripId = const Uuid().v4(),
        currentMileage = startMileage,
        startTimestamp = DateTime.now().toIso8601String();

  TripCategory get tripCategoryEnum {
    return TripCategory.values.firstWhere((e) => e.toString() == tripCategory);
  }

  TripStatus get tripStatusEnum =>
      TripStatus.values.firstWhere((e) => e.toString() == tripStatus);

  @override
  String toString() {
    return '''
Trip {
  id: $id,
  tripId: $tripId,
  driverId: ${driver.target?.uid},
  driverName: ${driver.target?.surname},
  startMileage: $startMileage,
  currentMileage: $currentMileage,
  endMileage: $endMileage,
  vin: $vin,
  startTimestamp: $startTimestamp,
  endTimestamp: $endTimestamp,
  tripCategory: $tripCategory,
  tripStatus: $tripStatus,
  startLocation: ${startLocation.target},
  endLocation: ${endLocation.target}
}
''';
  }
}
