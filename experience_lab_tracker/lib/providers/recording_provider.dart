// UPDATED: lib/providers/recording_provider.dart
// Stage 3 additions marked // + S3 : the start event now carries projectName
// and startedAtMillis, and there is a resumeIfActive() used on app launch.
// The background service owns writing/clearing the SessionStore.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/batch_upload.dart';
import '../models/project.dart';
import '../models/project_config.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import '../services/session_store.dart'; // + S3

class RecordingStatus {
  final bool recording;
  final bool loggingEnabled;
  final bool gforceActive;
  final double? lat, lon, acc;
  final String zone;
  final int gpsCount, accelCount, battery, elapsedSec;
  final String? lastUpload;
  final String? error;

  const RecordingStatus({
    this.recording = false,
    this.loggingEnabled = true,
    this.gforceActive = false,
    this.lat,
    this.lon,
    this.acc,
    this.zone = 'None',
    this.gpsCount = 0,
    this.accelCount = 0,
    this.battery = 0,
    this.elapsedSec = 0,
    this.lastUpload,
    this.error,
  });

  factory RecordingStatus.fromMap(Map<String, dynamic> m) => RecordingStatus(
        recording: m['recording'] as bool? ?? false,
        loggingEnabled: m['loggingEnabled'] as bool? ?? true,
        gforceActive: m['gforceActive'] as bool? ?? false,
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        acc: (m['acc'] as num?)?.toDouble(),
        zone: m['zone'] as String? ?? 'None',
        gpsCount: m['gpsCount'] as int? ?? 0,
        accelCount: m['accelCount'] as int? ?? 0,
        battery: m['battery'] as int? ?? 0,
        elapsedSec: m['elapsedSec'] as int? ?? 0,
        lastUpload: m['lastUpload'] as String?,
        error: m['error'] as String?,
      );
}

class RecordingProvider extends ChangeNotifier {
  final ApiService _api;
  final FlutterBackgroundService _service;

  RecordingProvider({ApiService? api, FlutterBackgroundService? service})
      : _api = api ?? ApiService(),
        _service = service ?? FlutterBackgroundService() {
    _statusSub = _service.on('status').listen((event) {
      if (event == null) return;
      status = RecordingStatus.fromMap(Map<String, dynamic>.from(event));
      notifyListeners();
    });
  }

  StreamSubscription<Map<String, dynamic>?>? _statusSub;
  RecordingStatus status = const RecordingStatus();
  String? actionError;
  bool busy = false;

  Future<bool> startRecording({
    required Project project,
    required ProjectConfig config,
    required String geojson,
    required String participantId,
  }) async {
    busy = true;
    actionError = null;
    notifyListeners();

    try {
      final phoneUuid = await DeviceService.getPhoneUuid();
      final deviceModel = await DeviceService.getDeviceModel();

      // 1. Lock the participant ID on the server.
      await _api.registerSession(BatchUpload.empty(
        projectId: project.id,
        participantId: participantId,
        phoneUuid: phoneUuid,
        deviceModel: deviceModel,
      ));

      // 2. Build the full session map. This is what the service persists and
      //    what the UI reads on relaunch, so it must be self-contained. // + S3
      final session = <String, dynamic>{
        'projectId': project.id,
        'projectName': project.name, // + S3 (needed to rebuild UI on reopen)
        'participantId': participantId,
        'phoneUuid': phoneUuid,
        'deviceModel': deviceModel,
        'config': config.toMap(),
        'geojson': geojson,
        'startedAtMillis': DateTime.now().millisecondsSinceEpoch, // + S3
      };

      // 3. Ensure the service is running.
      final running = await _service.isRunning();
      if (!running) {
        await _service.startService();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 4. Start recording. The service writes the SessionStore itself.
      _service.invoke('startRecording', session);

      busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      actionError = 'Could not start: $e';
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stopRecording() async {
    busy = true;
    notifyListeners();
    _service.invoke('stopRecording');
    await Future.delayed(const Duration(seconds: 2));
    _service.invoke('stopService');
    await SessionStore.clear(); // + S3 belt-and-braces; service also clears
    busy = false;
    status = const RecordingStatus();
    notifyListeners();
  }

  /// + S3: called on app launch. If a session is saved, make sure the service
  /// is running and (re)issue the start so a killed service resumes. Safe to
  /// call when already recording, because the service's start() is idempotent.
  Future<Map<String, dynamic>?> resumeIfActive() async {
    final session = await SessionStore.read();
    if (session == null) return null;

    final running = await _service.isRunning();
    if (!running) {
      await _service.startService();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _service.invoke('startRecording', session);
    return session;
  }

  /// + S3: is there a saved active session right now?
  static Future<Map<String, dynamic>?> activeSession() => SessionStore.read();

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
