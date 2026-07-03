import 'package:sensors_plus/sensors_plus.dart';

/// Central place for every value you might want to change later.
class AppConfig {
  /// Base URL of the FastAPI server (no trailing slash).
  /// This is the single most important setting. It must match the server
  /// the Streamlit dashboard writes to.
  static const String serverBaseUrl = 'https://gpstracker.buas.nl';

  /// How often (seconds) the app flushes its in-memory buffers to the server.
  /// The original Android app uses 60s. Keep it the same unless you have a reason.
  static const int uploadIntervalSeconds = 60;

  /// Accelerometer sampling period. The original app defaulted to ~100Hz.
  /// 100Hz produces ~6000 samples per 60s batch, which is a lot of data.
  /// SensorInterval.gameInterval is ~50Hz and is a sensible default.
  /// Change to Duration(milliseconds: 10) for ~100Hz if you truly need it.
  static const Duration accelSamplingPeriod = SensorInterval.gameInterval;

  /// Grace period (seconds) before an EXIT geofence action (STOP / DEACTIVATE)
  /// actually fires. Prevents GPS jitter at a zone edge from falsely stopping
  /// a recording. The original app uses 60s.
  static const int geofenceExitGraceSeconds = 60;

  /// How often the app polls the server for the next free participant ID
  /// while sitting on the recording screen (before Start is pressed).
  static const int participantPollSeconds = 15;

  /// Notification channel used by the Android foreground service.
  static const String notificationChannelId = 'explab_gps_tracking';
  static const String notificationChannelName = 'GPS Tracking';
  static const int notificationId = 8801;

  /// SharedPreferences keys.
  static const String prefPhoneUuid = 'phone_uuid';
}
