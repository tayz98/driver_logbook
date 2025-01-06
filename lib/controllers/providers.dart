import "package:elogbook/objectbox.g.dart";
import "package:elogbook/repositories/driver_repository.dart";
import "package:riverpod/riverpod.dart";
import "package:elogbook/repositories/trip_repository.dart";

final storeProvider = Provider<Store>((ref) {
  try {
    return openStore();
  } catch (e) {
    print('Failed to open ObjectBox store: $e');
    throw Exception('Could not initialize ObjectBox store');
  }
});

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  final store = ref.read(storeProvider);
  return DriverRepository(store);
});

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final store = ref.read(storeProvider);
  return TripRepository(store);
});
