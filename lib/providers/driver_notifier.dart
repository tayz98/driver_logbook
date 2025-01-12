import 'package:elogbook/models/driver.dart';
import 'package:elogbook/models/trip.dart';
import 'package:elogbook/providers/providers.dart';
import 'package:riverpod/riverpod.dart';

class DriverNotifier extends StateNotifier<Driver?> {
  final Ref ref;

  DriverNotifier(this.ref) : super(null) {
    final driver = ref.read(driverRepositoryProvider).getDriver();
    if (driver != null) {
      state = driver;
    }
  }

  void initializeDriver(String name, String surname) {
    if (state != null) {
      throw StateError("Driver has already exists.");
    }
    final driver = Driver(
      name: name,
      surname: surname,
      isAllowedToDoPrivateTrips: false,
    );
    ref.read(driverRepositoryProvider).saveDriver(driver);
    state = driver;
  }

  void changePermission(bool isAllowedToDoPrivateTrips) {
    if (state == null) {
      throw StateError("Driver has not been initialized yet.");
    }
    final updatedDriver =
        state!.copyWith(isAllowedToDoPrivateTrips: isAllowedToDoPrivateTrips);
    ref.read(driverRepositoryProvider).saveDriver(updatedDriver);
    state = updatedDriver;
  }

  void deleteDriver() {
    ref.read(driverRepositoryProvider).deleteDriver();
    state = null;
  }

  List<Trip> getTrips() {
    return state != null
        ? ref.read(driverRepositoryProvider).getTripsForDriver()
        : [];
  }
}
