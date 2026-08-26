// UPDATED: lib/services/background_service.dart
// Adds the experience sampling trigger engine. All additions are marked // + ES.
// If you prefer, diff this against your current file; the recording logic is
// unchanged, only ES pieces are inserted.

import 'dart:async';
import 'dart:convert'; // + ES

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../config/constants.dart';
import '../models/batch_upload.dart';
import '../models/experience_sampling.dart'; // + ES
import '../models/project_config.dart';
import '../models/sensor_points.dart';
import '../utils/geofence.dart';
import '../utils/timestamp.dart';
import 'accelerometer_service.dart';
import 'api_service.dart';
import 'geofence_service.dart';
import 'location_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

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

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
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

  // + ES: the UI tells us a prompt was answered/skipped so we don't re-log it.
  service.on('promptResolved').listen((event) {
    final id = event?['promptId'];
    if (id is String) session.resolvePrompt(id);
  });
}

class _RecordingSession {
  final ServiceInstance service;
  _RecordingSession(this.service);

  final ApiService _api = ApiService();
  final LocationService _location = LocationService();
  final AccelerometerService _accel = AccelerometerService();
  final Battery _battery = Battery();
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin(); // + ES

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _uploadTimer;
  Timer? _maxDurationTimer;
  Timer? _batteryTimer;

  GeofenceEvaluator? _geofence;

  late int _projectId;
  late String _participantId;
  late String _phoneUuid;
  late String _deviceModel;
  late ProjectConfig _config;

  final List<GpsPoint> _gpsBuffer = [];
  final List<AccelPoint> _accelBuffer = [];

  bool _recording = false;
  bool _loggingEnabled = true;
  bool _gforceActive = false;
  int _batteryLevel = 0;
  double? _lat, _lon, _acc;
  String _zone = 'None';
  DateTime? _startedAt;
  String? _lastUpload;
  String? _lastError;

  // + ES: experience sampling state
  ESConfig? _es;
  final Set<String> _firedPromptIds = {};
  final Map<String, Map<String, dynamic>> _pendingPrompts = {};
  final List<Timer> _esTimers = [];
  String _prevZoneForEs = 'None';

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

    final geofenceControlsStart = _config.geofencingEnabled &&
        _config.geofenceRules.any((r) =>
            r.trigger == 'ENTER' && r.action == 'START_GPS_LOGGING');
    _loggingEnabled = !geofenceControlsStart;

    if (_config.geofencingEnabled && geojson.trim().isNotEmpty) {
      final zones = parseGeoJson(geojson);
      _geofence = GeofenceEvaluator(
        zones: zones,
        rules: _config.geofenceRules,
        onAction: _handleGeofenceAction,
      );
    }

    if (service is AndroidServiceInstance) {
      (service as AndroidServiceInstance).setForegroundNotificationInfo(
        title: 'Recording $_participantId',
        content: 'Collecting GPS data',
      );
    }

    _refreshBattery();
    _batteryTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshBattery());

    _gpsSub = _location
        .start(intervalSeconds: _config.locationFrequencySec)
        .listen(_onPosition, onError: (e) => _lastError = 'GPS: $e');

    if (_gforceActive) _startAccel();

    _uploadTimer = Timer.periodic(
      Duration(seconds: AppConfig.uploadIntervalSeconds),
      (_) => _flush(),
    );

    final maxMs = (_config.maxDurationHrs * 3600 * 1000).round();
    if (maxMs > 0) {
      _maxDurationTimer = Timer(Duration(milliseconds: maxMs), () {
        _lastError = 'Max duration reached; stopping.';
        stop();
      });
    }

    await _setupExperienceSampling(); // + ES

    _emitStatus();
  }

  // ------------------------------------------------------------------ + ES
  Future<void> _setupExperienceSampling() async {
    _es = _config.experienceSampling;
    if (_es == null || !_es!.enabled || _es!.prompts.isEmpty) return;

    await _initNotif();

    for (final prompt in _es!.prompts) {
      final t = prompt.trigger;
      switch (t.type) {
        case 'elapsed_since_start':
          _esTimers.add(Timer(Duration(seconds: t.delaySec),
              () => _fireEsPrompt(prompt)));
          break;
        case 'random_in_window':
          final span = (t.windowEndSec - t.windowStartSec).clamp(0, 1 << 31);
          final offset = t.windowStartSec +
              (span == 0 ? 0 : (DateTime.now().microsecond % span));
          _esTimers
              .add(Timer(Duration(seconds: offset), () => _fireEsPrompt(prompt)));
          break;
        // geofence_enter and elapsed_since_geofence_enter are handled reactively
        // in _onPosition when a zone is entered.
      }
    }
  }

  Future<void> _initNotif() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _notif.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit));

    const channel = AndroidNotificationChannel(
      AppConfig.promptChannelId,
      AppConfig.promptChannelName,
      description: 'In-session questions that need your answer.',
      importance: Importance.high,
    );
    await _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _checkGeofenceEsTriggers(String enteredZone) {
    if (_es == null) return;
    for (final prompt in _es!.prompts) {
      final t = prompt.trigger;
      if (t.zone != enteredZone) continue;
      if (_firedPromptIds.contains(prompt.id)) continue;

      if (t.type == 'geofence_enter') {
        _fireEsPrompt(prompt);
      } else if (t.type == 'elapsed_since_geofence_enter') {
        _esTimers.add(Timer(Duration(seconds: t.delaySec),
            () => _fireEsPrompt(prompt)));
      }
    }
  }

  Future<void> _fireEsPrompt(ESPrompt prompt) async {
    if (!_recording) return;
    if (_firedPromptIds.contains(prompt.id)) return;
    _firedPromptIds.add(prompt.id);

    final ctx = {
      'promptId': prompt.id,
      'projectId': _projectId,
      'participantId': _participantId,
      'phoneUuid': _phoneUuid,
      'deviceModel': _deviceModel,
      'triggerType': prompt.trigger.type,
      'zone': _zone,
      'triggeredUtc': nowUtcTimestamp(),
      'questions': prompt.questions.map((q) => q.toMap()).toList(),
    };
    _pendingPrompts[prompt.id] = ctx;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        AppConfig.promptChannelId,
        AppConfig.promptChannelName,
        channelDescription: 'In-session questions that need your answer.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    final notifId =
        AppConfig.promptNotificationBaseId + (prompt.id.hashCode & 0xFFFF);
    await _notif.show(
      notifId,
      'Quick question',
      'Tap to answer a short question',
      details,
      payload: jsonEncode(ctx),
    );
  }

  void resolvePrompt(String promptId) {
    _pendingPrompts.remove(promptId);
  }

  Future<void> _flushSkippedPrompts() async {
    if (_pendingPrompts.isEmpty) return;
    for (final ctx in _pendingPrompts.values) {
      final questions = (ctx['questions'] as List)
          .map((q) => ESQuestion.fromMap(Map<String, dynamic>.from(q)))
          .toList();
      final now = nowUtcTimestamp();
      final records = questions
          .map((q) => ESResponseRecord(
                promptId: ctx['promptId'] as String,
                questionId: q.id,
                triggerType: ctx['triggerType'] as String? ?? '',
                zoneMarker: ctx['zone'] as String? ?? 'None',
                status: 'skipped',
                triggeredUtc: ctx['triggeredUtc'] as String? ?? now,
                timestampUtc: now,
              ))
          .toList();
      try {
        await _api.uploadExperienceSampling(
          projectId: ctx['projectId'] as int,
          participantId: ctx['participantId'] as String,
          phoneUuid: ctx['phoneUuid'] as String,
          deviceModel: ctx['deviceModel'] as String,
          responses: records,
        );
      } catch (_) {/* best effort */}
    }
    _pendingPrompts.clear();
  }
  // ------------------------------------------------------------- end + ES

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

    _zone = _geofence?.evaluate(p.latitude, p.longitude) ?? 'None';

    // + ES: detect a zone entry transition and check geofence-based prompts.
    if (_zone != _prevZoneForEs) {
      if (_zone != 'None') _checkGeofenceEsTriggers(_zone);
      _prevZoneForEs = _zone;
    }

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
        break;
    }
    _emitStatus();
  }

  Future<void> _refreshBattery() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
    } catch (_) {}
  }

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

    // + ES: cancel pending triggers and log any unanswered prompts as skipped.
    for (final t in _esTimers) {
      t.cancel();
    }
    _esTimers.clear();
    await _flushSkippedPrompts();

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
