import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/constants.dart';

/// Provides the two device-identity values every upload needs:
/// a persistent phone UUID (generated once, stored on disk) and a
/// human-readable device model string.
class DeviceService {
  /// Returns the phone UUID, generating and persisting one on first call.
  static Future<String> getPhoneUuid() async {
    final prefs = await SharedPreferences.getInstance();
    var uuid = prefs.getString(AppConfig.prefPhoneUuid);
    if (uuid == null || uuid.isEmpty) {
      uuid = const Uuid().v4();
      await prefs.setString(AppConfig.prefPhoneUuid, uuid);
    }
    return uuid;
  }

  /// Returns a readable device model, e.g. "SM-A166B" or "iPhone15,3".
  static Future<String> getDeviceModel() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return a.model; // e.g. "moto g 5G"
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        // utsname.machine is the precise hardware id (e.g. "iPhone15,3").
        return i.utsname.machine;
      }
    } catch (_) {
      // fall through
    }
    return 'unknown';
  }
}
