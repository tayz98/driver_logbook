import "package:elogbook/models/trip.dart";
import "package:elogbook/objectbox.g.dart";
import "package:elogbook/providers/trip_provider.dart";
import "package:elogbook/repositories/driver_repository.dart";
import "package:elogbook/services/custom_bluetooth_service.dart";
import "package:elogbook/services/elm327_services.dart";
import "package:riverpod/riverpod.dart";
import "package:elogbook/repositories/trip_repository.dart";
import "package:elogbook/repositories/telemetry_repository.dart";
import 'package:path_provider/path_provider.dart';

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

final customBluetoothServiceProvider = Provider<CustomBluetoothService>((ref) {
  final service = CustomBluetoothService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final elm327ServiceStreamProvider = StreamProvider<Elm327Service?>((ref) {
  final bluetoothService = ref.watch(customBluetoothServiceProvider);
  return bluetoothService.elm327ServiceStream;
});

final tripNotifierProvider = StateNotifierProvider<TripNotifier, Trip?>((ref) {
  final tripRepository = ref.watch(tripRepositoryProvider);
  final driverRepository = ref.watch(driverRepositoryProvider);
  final elm327Async = ref.watch(elm327ServiceStreamProvider);

  return elm327Async.when(
    data: (elm327Service) {
      if (elm327Service != null) {
        return TripNotifier(tripRepository, elm327Service, driverRepository);
      } else {
        return TripNotifier(tripRepository, null,
            driverRepository); // Handle null appropriately
      }
    },
    loading: () => TripNotifier(tripRepository, null, driverRepository),
    error: (_, __) => TripNotifier(tripRepository, null, driverRepository),
  );
});
