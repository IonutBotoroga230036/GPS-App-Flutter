import 'dart:io';

import 'package:geolocator/geolocator.dart';

/// Wraps geolocator into a simple start/stop position stream. The platform
/// settings here are what make background GPS work:
///  - Android: a foreground service notification keeps the stream alive.
///  - iOS: allowBackgroundLocationUpdates keeps it alive when backgrounded.
class LocationService {
  Stream<Position>? _stream;

  /// Begins a high-accuracy position stream at roughly [intervalSeconds].
  /// distanceFilter is 0 so we get time-based updates, not distance-based.
  Stream<Position> start({required int intervalSeconds}) {
    final LocationSettings settings;

    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: Duration(seconds: intervalSeconds),
        // We run our own foreground service via flutter_background_service,
        // so we do NOT ask geolocator to start a second one.
        foregroundNotificationConfig: null,
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        // This is the key flag for iOS background GPS. Requires the
        // "location" background mode in Info.plist and "Always" permission.
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        activityType: ActivityType.fitness,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }

    _stream = Geolocator.getPositionStream(locationSettings: settings);
    return _stream!;
  }

  /// geolocator stops the platform updates automatically when the stream
  /// subscription is cancelled, so there is nothing to tear down here.
  void stop() {
    _stream = null;
  }
}
