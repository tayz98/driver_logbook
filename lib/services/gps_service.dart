import 'dart:io';

import 'package:driver_logbook/utils/custom_log.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:driver_logbook/models/trip_location.dart';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;

  Future<Position?> get currentPosition async {
    try {
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      return await Geolocator.getLastKnownPosition();
    }
  }
  // Future<Position?> get lastKnownPosition async =>
  //     await Geolocator.getLastKnownPosition();

  late LocationSettings _locationSettings;
  LocationSettings get locationSettings => _locationSettings;
  LocationPermission? _locationPermission;
  LocationPermission? get locationPermission => _locationPermission;

  GpsService._internal() {
    _initialize();
    setLocaleIdentifier('de_DE');
    _checkStatusAndPermissions();
  }

  void _initialize() {
    if (Platform.isAndroid) {
      _locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 250,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText: "Location service is running",
              notificationTitle: "Location service",
              enableWakeLock: true));
    } else if (Platform.isIOS) {
      _locationSettings = AppleSettings(
          accuracy: LocationAccuracy.medium,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 200,
          // timeLimit: const Duration(seconds: 4),
          pauseLocationUpdatesAutomatically: true,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true);
    }
  }

  Future<void> _checkStatusAndPermissions() async {
    bool serviceEnabled;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    _locationPermission = await Geolocator.checkPermission();
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
      if (_locationPermission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (_locationPermission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }
  }

  Future<TripLocation>? getLocationFromCurrentPosition() async {
    final Position? position = await currentPosition;
    if (position == null) {
      CustomLogger.e('Position could not be determined');
    }
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
          position!.latitude, position.longitude);
      return TripLocation(
        street: placemarks.first.street ?? '',
        city: placemarks.first.locality ?? '',
        postalCode: placemarks.first.postalCode ?? '',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      return TripLocation(
        street: '',
        city: '',
        postalCode: '',
        latitude: position!.latitude,
        longitude: position.longitude,
      );
    }
  }
}
