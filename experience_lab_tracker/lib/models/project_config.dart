// UPDATED: lib/models/project_config.dart
// Adds an `experienceSampling` field parsed from the same config JSON and
// threaded through toMap/fromMap so it reaches the background isolate.
// The only additions versus the original are marked with // + ES.

import 'experience_sampling.dart'; // + ES

class GeofenceRule {
  final String trigger;
  final String action;
  const GeofenceRule({required this.trigger, required this.action});
  factory GeofenceRule.fromJson(Map<String, dynamic> json) => GeofenceRule(
        trigger: (json['trigger'] ?? '').toString().toUpperCase(),
        action: (json['action'] ?? '').toString().toUpperCase(),
      );
}

class ProjectConfig {
  final double maxDurationHrs;
  final bool gForceEnabled;
  final bool locationEnabled;
  final int locationFrequencySec;
  final bool geofencingEnabled;
  final List<GeofenceRule> geofenceRules;
  final ESConfig? experienceSampling; // + ES

  const ProjectConfig({
    required this.maxDurationHrs,
    required this.gForceEnabled,
    required this.locationEnabled,
    required this.locationFrequencySec,
    required this.geofencingEnabled,
    required this.geofenceRules,
    this.experienceSampling, // + ES
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

    double toDouble(dynamic v, double fb) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fb;
    int toInt(dynamic v, int fb) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fb;
    bool toBool(dynamic v, bool fb) {
      if (v is bool) return v;
      final s = v?.toString().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return fb;
    }

    // + ES: parse the experience_sampling block if present.
    final esRaw = json['experience_sampling'];
    final es = esRaw is Map<String, dynamic> ? ESConfig.fromJson(esRaw) : null;

    return ProjectConfig(
      maxDurationHrs: toDouble(limit['max_duration_hrs'], 3.0),
      gForceEnabled: toBool(gforce['enabled'], false),
      locationEnabled: toBool(loc['enabled'], true),
      locationFrequencySec: toInt(loc['frequency_sec'], 1),
      geofencingEnabled: toBool(geo['enabled'], false),
      geofenceRules: rules,
      experienceSampling: es, // + ES
    );
  }

  Map<String, dynamic> toMap() => {
        'maxDurationHrs': maxDurationHrs,
        'gForceEnabled': gForceEnabled,
        'locationEnabled': locationEnabled,
        'locationFrequencySec': locationFrequencySec,
        'geofencingEnabled': geofencingEnabled,
        'geofenceRules': geofenceRules
            .map((r) => {'trigger': r.trigger, 'action': r.action})
            .toList(),
        'experienceSampling': experienceSampling?.toMap(), // + ES
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
        experienceSampling: m['experienceSampling'] == null // + ES
            ? null
            : ESConfig.fromMap(Map<String, dynamic>.from(m['experienceSampling'])),
      );
}
