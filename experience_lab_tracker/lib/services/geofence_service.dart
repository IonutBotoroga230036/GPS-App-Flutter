import 'dart:async';

import '../config/constants.dart';
import '../models/project_config.dart';
import '../utils/geofence.dart';

/// The actions a geofence rule can request. The evaluator reports these to its
/// owner (the background service) which actually toggles logging / g-force.
enum GeofenceAction {
  startLogging,
  stopLogging,
  activateGforce,
  deactivateGforce,
  markerOnly,
}

/// Evaluates polygon geofences on each GPS fix and drives enter/exit actions.
///
/// Faithful to the Android LocationProcessor:
///  - The current zone is recomputed on every fix.
///  - Entering a zone fires ENTER-triggered actions immediately.
///  - Leaving all zones fires EXIT-triggered actions after a grace period
///    (default 60s) so GPS jitter at a boundary doesn't falsely stop a run.
///  - Re-entering during the grace window cancels the pending EXIT actions.
class GeofenceEvaluator {
  final List<GeoZone> _zones;
  final List<GeofenceRule> _rules;
  final void Function(GeofenceAction action) onAction;

  String? _currentZone; // null == outside all zones
  Timer? _exitGraceTimer;

  GeofenceEvaluator({
    required List<GeoZone> zones,
    required List<GeofenceRule> rules,
    required this.onAction,
  })  : _zones = zones,
        _rules = rules;

  /// The zone name to stamp on data points right now. "None" when outside.
  String get currentZoneMarker => _currentZone ?? 'None';

  /// Call on every GPS fix. Returns the zone marker for this point.
  String evaluate(double lat, double lon) {
    final newZone = zoneForPoint(lat, lon, _zones); // null if outside

    if (newZone == _currentZone) {
      return currentZoneMarker; // no transition
    }

    // A transition happened.
    if (newZone != null) {
      // Entered a zone (or moved directly into a different one).
      _cancelExitGrace();
      _currentZone = newZone;
      _fire('ENTER');
    } else {
      // Left all zones -> schedule EXIT actions after the grace period.
      _scheduleExit();
    }

    return currentZoneMarker;
  }

  void _scheduleExit() {
    _cancelExitGrace();
    _exitGraceTimer = Timer(
      const Duration(seconds: AppConfig.geofenceExitGraceSeconds),
      () {
        _currentZone = null;
        _fire('EXIT');
      },
    );
  }

  void _cancelExitGrace() {
    _exitGraceTimer?.cancel();
    _exitGraceTimer = null;
  }

  void _fire(String trigger) {
    for (final rule in _rules) {
      if (rule.trigger != trigger) continue;
      switch (rule.action) {
        case 'START_GPS_LOGGING':
          onAction(GeofenceAction.startLogging);
          break;
        case 'STOP_GPS_LOGGING':
          onAction(GeofenceAction.stopLogging);
          break;
        case 'ACTIVATE_GFORCE':
          onAction(GeofenceAction.activateGforce);
          break;
        case 'DEACTIVATE_GFORCE':
          onAction(GeofenceAction.deactivateGforce);
          break;
        case 'MARKER_ONLY':
          onAction(GeofenceAction.markerOnly);
          break;
      }
    }
  }

  void dispose() => _cancelExitGrace();
}
