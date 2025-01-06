import './location.dart';
import './trip_information.dart';
import './trip_status.dart';
import './trip_category.dart';
import './telemetry.dart';

class Trip {
  TripInformation tripInformation;
  Location startLocation;
  Location? endLocation;
  double startMileage;
  double? endMileage;
  TripCategory tripCategory;
  TripStatus tripStatus = TripStatus.inProgress;
  Telemetry? telemetry;

  Trip({
    required this.tripInformation,
    required this.startLocation,
    this.endLocation,
    required this.tripStatus,
    required this.startMileage,
    this.endMileage,
    required this.tripCategory,
  });
}
