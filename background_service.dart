import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../config/constants.dart';
import '../models/batch_upload.dart';
import '../models/project_config.dart';
import '../models/sensor_points.dart';
import '../utils/geofence.dart';
import '../utils/timestamp.dart';
import 'accelerometer_service.dart';
import 'api_service.dart';
import 'geofence_service.dart';
import 'location_service.dart';

/// ===========================================================================
/// BACKGROUND SERVICE
///
/// Everything below `onStart` runs inside a SEPARATE isolate on Android (and a
/// background execution context on iOS). It cannot see your widgets or your
/// providers. All communication happens through messages:
///   UI  -> service : FlutterBackgroundService().invoke('name', {payload})
///   service -> UI  : service.invoke('name', {payload}) + UI listens with .on()
///
/// Messages this service understands:
///   'startRecording' {projectId, participantId, phoneUuid, deviceModel,
///                     config, geojson}
///   'stopRecording'  {}
///   'stopService'    {}
///
/// Messages this service emits:
///   'status' {recording, loggingEnabled, lat, lon, acc, zone,
///             gpsCount, accelCount, lastUpload, elapsedSec, error}
/// ===========================================================================

/// Call once at app launch (in main()) to register the service.
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Android needs a notification channel for the foreground service.
  final notifications = FlutterLocalNotificationsPlugin();
  const channel = AndroidNotificationChannel(
    AppConfig.notificationChannelId,
    AppConfig.notificationChannelName,
    description: 'Keeps GPS recording alive in the background.',
    importance: Importance.low,
  );
  await notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: false,
      notificationChannelId: AppConfig.notificationChannelId,
      initialNotificationTitle: 'Experience Lab',
      initialNotificationContent: 'Ready',
      foregroundServiceNotificationId: AppConfig.notificationId,
      // Declare the foreground service types this work requires.
      foregroundServiceTypes: [
        AndroidForegroundType.location,
        AndroidForegroundType.dataSync,
      ],
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: onIosBackground,
      autoStart: false,
    ),
  );
}

/// iOS background fetch handler. iOS only grants short windows; the real
/// continuous GPS in background comes from the location background mode, not
/// from this callback. We return true to signal the work completed.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

/// The isolate entry point. Must be a top-level / static function and marked
/// with @pragma('vm:entry-point') so the AOT compiler keeps it.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Plugins must be re-registered inside the background isolate.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final session = _RecordingSession(service);

  service.on('startRecording').listen((event) {
    if (event == null) return;
    session.start(event);
  });

  service.on('stopRecording').listen((event) {
    session.stop();
  });

  service.on('stopService').listen((event) async {
    await session.stop();
    service.stopSelf();
  });
}

/// Holds all mutable recording state inside the isolate.
class _RecordingSession {
  final ServiceInstance service;
  _RecordingSession(this.service);

  final ApiService _api = ApiService();
  final LocationService _location = LocationService();
  final AccelerometerService _accel = AccelerometerService();
  final Battery _battery = Battery();

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _uploadTimer;
  Timer? _maxDurationTimer;
  Timer? _batteryTimer;

  GeofenceEvaluator? _geofence;

  // Identity for this session.
  late int _projectId;
  late String _participantId;
  late String _phoneUuid;
  late String _deviceModel;
  late ProjectConfig _config;

  // Buffers (plain lists; the isolate is single-threaded so no locks needed).
  final List<GpsPoint> _gpsBuffer = [];
  final List<AccelPoint> _accelBuffer = [];

  // Live state.
  bool _recording = false;
  bool _loggingEnabled = true; // gated by geofence START/STOP actions
  bool _gforceActive = false;
  int _batteryLevel = 0;
  double? _lat, _lon, _acc;
  String _zone = 'None';
  DateTime? _startedAt;
  String? _lastUpload;
  String? _lastError;

  Future<void> start(Map<String, dynamic> event) async {
    if (_recording) return;

    _projectId = event['projectId'] as int;
    _participantId = event['participantId'] as String;
    _phoneUuid = event['phoneUuid'] as String;
    _deviceModel = event['deviceModel'] as String;
    _config =
        ProjectConfig.fromMap(Map<String, dynamic>.from(event['config'] as Map));
    final geojson = (event['geojson'] as String?) ?? '';

    _recording = true;
    _startedAt = DateTime.now();
    _gforceActive = _config.gForceEnabled;

    // If geofencing drives logging (an ENTER->START rule exists), start with
    // logging OFF and let the zone turn it on. Otherwise log immediately.
    final geofenceControlsStart = _config.geofencingEnabled &&
        _config.geofenceRules.any((r) =>
            r.trigger == 'ENTER' && r.action == 'START_GPS_LOGGING');
    _loggingEnabled = !geofenceControlsStart;

    // Build the geofence evaluator if enabled.
    if (_config.geofencingEnabled && geojson.trim().isNotEmpty) {
      final zones = parseGeoJson(geojson);
      _geofence = GeofenceEvaluator(
        zones: zones,
        rules: _config.geofenceRules,
        onAction: _handleGeofenceAction,
      );
    }

    // Update the foreground notification.
    if (service is AndroidServiceInstance) {
      (service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: 'Recording $_participantId',
        content: 'Collecting GPS data',
      );
    }

    // Prime battery level and refresh it periodically.
    _refreshBattery();
    _batteryTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshBattery());

    // Start GPS.
    _gpsSub = _location
        .start(intervalSeconds: _config.locationFrequencySec)
        .listen(_onPosition, onError: (e) => _lastError = 'GPS: $e');

    // Start accelerometer if enabled.
    if (_gforceActive) _startAccel();

    // 60-second upload loop.
    _uploadTimer = Timer.periodic(
      Duration(seconds: AppConfig.uploadIntervalSeconds),
      (_) => _flush(),
    );

    // Auto-stop after the max experiment duration.
    final maxMs = (_config.maxDurationHrs * 3600 * 1000).round();
    if (maxMs > 0) {
      _maxDurationTimer = Timer(Duration(milliseconds: maxMs), () {
        _lastError = 'Max duration reached; stopping.';
        stop();
      });
    }

    _emitStatus();
  }

  void _startAccel() {
    _accelSub?.cancel();
    _accelSub = _accel.start().listen((e) {
      if (!_recording || !_loggingEnabled || !_gforceActive) return;
      _accelBuffer.add(AccelPoint(
        x: e.x,
        y: e.y,
        z: e.z,
        zone: _zone,
        time: nowUtcTimestamp(),
      ));
    }, onError: (e) => _lastError = 'Accel: $e');
  }

  void _onPosition(Position p) {
    _lat = p.latitude;
    _lon = p.longitude;
    _acc = p.accuracy;

    // Evaluate geofence; this may fire actions that toggle logging/gforce.
    _zone = _geofence?.evaluate(p.latitude, p.longitude) ?? 'None';

    if (_recording && _loggingEnabled) {
      _gpsBuffer.add(GpsPoint(
        lat: p.latitude,
        lon: p.longitude,
        acc: p.accuracy,
        zone: _zone,
        time: nowUtcTimestamp(),
        battery: _batteryLevel,
      ));
    }
    _emitStatus();
  }

  void _handleGeofenceAction(GeofenceAction action) {
    switch (action) {
      case GeofenceAction.startLogging:
        _loggingEnabled = true;
        break;
      case GeofenceAction.stopLogging:
        _loggingEnabled = false;
        break;
      case GeofenceAction.activateGforce:
        _gforceActive = true;
        if (_accelSub == null) _startAccel();
        break;
      case GeofenceAction.deactivateGforce:
        _gforceActive = false;
        break;
      case GeofenceAction.markerOnly:
        break; // zone tagging already handled
    }
    _emitStatus();
  }

  Future<void> _refreshBattery() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
    } catch (_) {
      // some emulators throw; leave previous value
    }
  }

  /// Snapshot the buffers and POST them. On success clear what we sent;
  /// on failure keep the data and retry next cycle (so brief outages are safe).
  Future<void> _flush() async {
    if (_gpsBuffer.isEmpty && _accelBuffer.isEmpty) return;

    final gpsSnapshot = List<GpsPoint>.from(_gpsBuffer);
    final accelSnapshot = List<AccelPoint>.from(_accelBuffer);

    final payload = BatchUpload(
      projectId: _projectId,
      participantId: _participantId,
      phoneUuid: _phoneUuid,
      deviceModel: _deviceModel,
      gpsData: gpsSnapshot,
      accelData: accelSnapshot,
    );

    try {
      await _api.ingest(payload);
      // Remove exactly what we sent (new points may have arrived meanwhile).
      _gpsBuffer.removeRange(0, gpsSnapshot.length);
      _accelBuffer.removeRange(0, accelSnapshot.length);
      _lastUpload = nowUtcTimestamp();
      _lastError = null;
    } catch (e) {
      _lastError = 'Upload failed (will retry): $e';
    }
    _emitStatus();
  }

  Future<void> stop() async {
    if (!_recording) return;
    _recording = false;

    await _gpsSub?.cancel();
    _gpsSub = null;
    _location.stop();

    await _accelSub?.cancel();
    _accelSub = null;

    _uploadTimer?.cancel();
    _maxDurationTimer?.cancel();
    _batteryTimer?.cancel();
    _geofence?.dispose();

    // Final flush of whatever is left.
    await _flush();

    _gpsBuffer.clear();
    _accelBuffer.clear();

    if (service is AndroidServiceInstance) {
      (service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: 'Experience Lab',
        content: 'Stopped',
      );
    }

    _emitStatus();
  }

  void _emitStatus() {
    final elapsed = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inSeconds;
    service.invoke('status', {
      'recording': _recording,
      'loggingEnabled': _loggingEnabled,
      'gforceActive': _gforceActive,
      'lat': _lat,
      'lon': _lon,
      'acc': _acc,
      'zone': _zone,
      'gpsCount': _gpsBuffer.length,
      'accelCount': _accelBuffer.length,
      'battery': _batteryLevel,
      'lastUpload': _lastUpload,
      'elapsedSec': elapsed,
      'error': _lastError,
    });
  }
}
