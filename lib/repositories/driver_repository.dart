import 'package:objectbox/objectbox.dart';
import '../models/driver.dart';

class DriverRepository {
  final Box<Driver> _driverBox;

  DriverRepository(Store store) : _driverBox = store.box<Driver>();

  Driver? getDriver() {
    return _driverBox.getAll().firstOrNull;
  }

  // Save a driver
  void saveDriver(Driver driver) {
    _driverBox.put(driver);
  }

  // Delete the single Driver
  void deleteDriver() {
    final driver = getDriver();
    if (driver != null) {
      _driverBox.remove(driver.id);
    }
  }
}
