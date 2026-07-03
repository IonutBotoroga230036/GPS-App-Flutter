/// A single geofence rule, e.g. {"trigger": "ENTER", "action": "START_GPS_LOGGING"}.
class GeofenceRule {
  final String trigger; // "ENTER" or "EXIT"
  final String action; // START_GPS_LOGGING, STOP_GPS_LOGGING, ACTIVATE_GFORCE, ...

  const GeofenceRule({required this.trigger, required this.action});

  factory GeofenceRule.fromJson(Map<String, dynamic> json) => GeofenceRule(
        trigger: (json['trigger'] ?? '').toString().toUpperCase(),
        action: (json['action'] ?? '').toString().toUpperCase(),
      );
}

/// Parsed form of the `config_json` blob returned by
/// `GET /projects/{name}/settings`. Mirrors the schema the Streamlit
/// dashboard writes. Every field is optional and defaulted, because older
/// projects may not contain every key.
class ProjectConfig {
  final double maxDurationHrs; // experiment_limit.max_duration_hrs
  final bool gForceEnabled; // g_force.enabled
  final bool locationEnabled; // location_tracking.enabled
  final int locationFrequencySec; // location_tracking.frequency_sec
  final bool geofencingEnabled; // geo_fencing.enabled
  final List<GeofenceRule> geofenceRules; // geo_fencing.rules

  const ProjectConfig({
    required this.maxDurationHrs,
    required this.gForceEnabled,
    required this.locationEnabled,
    required this.locationFrequencySec,
    required this.geofencingEnabled,
    required this.geofenceRules,
  });

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final v = json[key];
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    }

    final limit = section('experiment_limit');
    final gforce = section('g_force');
    final loc = section('location_tracking');
    final geo = section('geo_fencing');

    final rulesRaw = geo['rules'];
    final rules = <GeofenceRule>[];
    if (rulesRaw is List) {
      for (final r in rulesRaw) {
        if (r is Map<String, dynamic>) rules.add(GeofenceRule.fromJson(r));
      }
    }

    double toDouble(dynamic v, double fallback) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }

    int toInt(dynamic v, int fallback) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    bool toBool(dynamic v, bool fallback) {
      if (v is bool) return v;
      final s = v?.toString().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return fallback;
    }

    return ProjectConfig(
      maxDurationHrs: toDouble(limit['max_duration_hrs'], 3.0),
      gForceEnabled: toBool(gforce['enabled'], false),
      locationEnabled: toBool(loc['enabled'], true),
      locationFrequencySec: toInt(loc['frequency_sec'], 1),
      geofencingEnabled: toBool(geo['enabled'], false),
      geofenceRules: rules,
    );
  }

  /// Serialize back to a map so it can be passed across the isolate boundary
  /// to the background service (which cannot share Dart objects directly).
  Map<String, dynamic> toMap() => {
        'maxDurationHrs': maxDurationHrs,
        'gForceEnabled': gForceEnabled,
        'locationEnabled': locationEnabled,
        'locationFrequencySec': locationFrequencySec,
        'geofencingEnabled': geofencingEnabled,
        'geofenceRules': geofenceRules
            .map((r) => {'trigger': r.trigger, 'action': r.action})
            .toList(),
      };

  factory ProjectConfig.fromMap(Map<String, dynamic> m) => ProjectConfig(
        maxDurationHrs: (m['maxDurationHrs'] as num).toDouble(),
        gForceEnabled: m['gForceEnabled'] as bool,
        locationEnabled: m['locationEnabled'] as bool,
        locationFrequencySec: m['locationFrequencySec'] as int,
        geofencingEnabled: m['geofencingEnabled'] as bool,
        geofenceRules: (m['geofenceRules'] as List)
            .map((e) => GeofenceRule(
                  trigger: e['trigger'] as String,
                  action: e['action'] as String,
                ))
            .toList(),
      );
}
