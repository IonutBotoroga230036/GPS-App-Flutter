import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/batch_upload.dart';
import '../models/project.dart';
import '../models/project_config.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';

/// A snapshot of recording status pushed up from the background isolate.
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

/// Bridges the UI and the background service. Sends start/stop commands and
/// republishes the status messages the isolate emits.
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

  /// Registers the session on the server then starts background collection.
  /// Returns true on success.
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

      // 2. Make sure the background service is running.
      final running = await _service.isRunning();
      if (!running) {
        await _service.startService();
        // give the isolate a moment to register its listeners
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 3. Tell it to start recording with this session's parameters.
      _service.invoke('startRecording', {
        'projectId': project.id,
        'participantId': participantId,
        'phoneUuid': phoneUuid,
        'deviceModel': deviceModel,
        'config': config.toMap(),
        'geojson': geojson,
      });

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
    // Let the final flush happen, then tear the service down.
    await Future.delayed(const Duration(seconds: 2));
    _service.invoke('stopService');
    busy = false;
    status = const RecordingStatus();
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
