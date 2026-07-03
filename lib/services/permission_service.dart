import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of the permission request flow.
class PermissionResult {
  final bool granted;
  final String message;
  const PermissionResult(this.granted, this.message);
}

/// Centralizes the permission dance. The order matters:
/// 1. Location services must be ON.
/// 2. Foreground (while-in-use) location must be granted first.
/// 3. THEN background ("always") location can be requested.
/// 4. Notifications (Android 13+) for the foreground service.
class PermissionService {
  /// Requests everything needed to record in the background.
  static Future<PermissionResult> requestAll() async {
    // 1. Location services enabled?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const PermissionResult(
          false, 'Location services are turned off. Enable GPS and retry.');
    }

    // 2. Foreground location.
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return const PermissionResult(false, 'Location permission denied.');
    }
    if (perm == LocationPermission.deniedForever) {
      return const PermissionResult(
          false,
          'Location permission permanently denied. '
          'Enable it in system settings.');
    }

    // 3. Notifications (needed for the Android foreground service notification).
    if (Platform.isAndroid) {
      final notif = await Permission.notification.status;
      if (!notif.isGranted) {
        await Permission.notification.request();
      }
    }

    // 4. Background ("always") location. On Android 10+ this is a separate
    // grant; on iOS it is the "Always" location authorization. We request it
    // but do not hard-fail if the user only grants while-in-use, because
    // recording still works while the screen is on.
    if (Platform.isAndroid) {
      final bg = await Permission.locationAlways.status;
      if (!bg.isGranted) {
        await Permission.locationAlways.request();
      }
    } else if (Platform.isIOS) {
      // Re-checking permission triggers the iOS "Always Allow" upgrade prompt
      // once while-in-use has been granted.
      await Geolocator.requestPermission();
    }

    return const PermissionResult(true, 'Permissions granted.');
  }

  static Future<bool> hasForegroundLocation() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }
}
