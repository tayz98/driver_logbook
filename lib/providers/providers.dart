import "package:elogbook/models/driver.dart";
import "package:elogbook/models/trip.dart";
import "package:elogbook/objectbox.g.dart";
import "package:elogbook/providers/driver_notifier.dart";
import "package:elogbook/providers/trip_notifier.dart";
import "package:elogbook/repositories/driver_repository.dart";
import "package:elogbook/services/custom_bluetooth_service.dart";
import "package:riverpod/riverpod.dart";
import "package:elogbook/repositories/trip_repository.dart";

final storeProvider = Provider<Store>((ref) {
  throw UnimplementedError();
});

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  final store = ref.read(storeProvider);
  return DriverRepository(store);
});

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final store = ref.read(storeProvider);
  return TripRepository(store);
});

final tripProvider = StateNotifierProvider<TripNotifier, Trip>((ref) {
  return TripNotifier(ref);
});

final driverProvider = StateNotifierProvider<DriverNotifier, Driver?>((ref) {
  return DriverNotifier(ref);
});

final customBluetoothServiceProvider = Provider<CustomBluetoothService>((ref) {
  return CustomBluetoothService(ref);
});
