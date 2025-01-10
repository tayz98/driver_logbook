import "package:elogbook/models/trip.dart";
import "package:elogbook/objectbox.g.dart";
import "package:elogbook/providers/trip_notifier.dart";
import "package:elogbook/repositories/driver_repository.dart";
import "package:elogbook/services/custom_bluetooth_service.dart";
import "package:riverpod/riverpod.dart";
import "package:elogbook/repositories/trip_repository.dart";
import "package:elogbook/repositories/telemetry_repository.dart";

final storeProvider = Provider<Store>((ref) {
  throw UnimplementedError(); // This will be overridden in main()
});

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  final store = ref.read(storeProvider);
  return DriverRepository(store);
});

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final store = ref.read(storeProvider);
  return TripRepository(store);
});

final telemetryRepositoryProvider = Provider<TelemetryRepository>((ref) {
  final store = ref.read(storeProvider);
  return TelemetryRepository(store);
});

final tripProvider = StateNotifierProvider<TripNotifier, Trip>(
  (ref) => TripNotifier(),
);
final customBluetoothServiceProvider = Provider<CustomBluetoothService>((ref) {
  return CustomBluetoothService(ref);
});
