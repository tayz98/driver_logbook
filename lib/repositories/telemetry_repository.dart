import 'package:objectbox/objectbox.dart';
import '../models/telemetry.dart';

class TelemetryRepository {
  final Box<Telemetry> _telemetryBox;

  TelemetryRepository(Store store) : _telemetryBox = store.box<Telemetry>();

  void saveTelemetry(Telemetry telemetry) {
    _telemetryBox.put(telemetry);
  }
}
