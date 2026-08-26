// Experience sampling data models.
// Place at: lib/models/experience_sampling.dart
//
// These parse the `experience_sampling` block of the project config JSON, and
// define the outgoing response record. They include toMap/fromMap so the whole
// config can cross the background-isolate boundary (the trigger engine runs in
// the isolate, like the GPS and geofence logic).

/// One question inside a prompt.
class ESQuestion {
  final String id;
  final String type; // scale | slider | multiple_choice | open
  final String text;

  // scale
  final int points;
  final List<String> labels;

  // slider
  final double min;
  final double max;
  final double step;
  final String minLabel;
  final String maxLabel;

  // multiple choice
  final List<String> options;
  final bool multiple;

  const ESQuestion({
    required this.id,
    required this.type,
    required this.text,
    this.points = 5,
    this.labels = const [],
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.minLabel = '',
    this.maxLabel = '',
    this.options = const [],
    this.multiple = false,
  });

  factory ESQuestion.fromJson(Map<String, dynamic> j) {
    double d(dynamic v, double fb) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fb;
    int i(dynamic v, int fb) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fb;
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];

    return ESQuestion(
      id: (j['id'] ?? 'q').toString(),
      type: (j['type'] ?? 'open').toString(),
      text: (j['text'] ?? '').toString(),
      points: i(j['points'], 5),
      labels: strList(j['labels']),
      min: d(j['min'], 0),
      max: d(j['max'], 100),
      step: d(j['step'], 1),
      minLabel: (j['min_label'] ?? '').toString(),
      maxLabel: (j['max_label'] ?? '').toString(),
      options: strList(j['options']),
      multiple: j['multiple'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id, 'type': type, 'text': text, 'points': points,
        'labels': labels, 'min': min, 'max': max, 'step': step,
        'min_label': minLabel, 'max_label': maxLabel,
        'options': options, 'multiple': multiple,
      };

  factory ESQuestion.fromMap(Map<String, dynamic> m) => ESQuestion.fromJson(m);
}

/// The trigger condition for a prompt.
class ESTrigger {
  final String type; // geofence_enter | elapsed_since_start | elapsed_since_geofence_enter | random_in_window
  final String? zone;
  final int delaySec;
  final int windowStartSec;
  final int windowEndSec;

  const ESTrigger({
    required this.type,
    this.zone,
    this.delaySec = 0,
    this.windowStartSec = 0,
    this.windowEndSec = 0,
  });

  factory ESTrigger.fromJson(Map<String, dynamic> j) {
    int i(dynamic v, int fb) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fb;
    return ESTrigger(
      type: (j['type'] ?? 'elapsed_since_start').toString(),
      zone: j['zone']?.toString(),
      delaySec: i(j['delay_sec'], 0),
      windowStartSec: i(j['window_start_sec'], 0),
      windowEndSec: i(j['window_end_sec'], 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type, 'zone': zone, 'delay_sec': delaySec,
        'window_start_sec': windowStartSec, 'window_end_sec': windowEndSec,
      };

  factory ESTrigger.fromMap(Map<String, dynamic> m) => ESTrigger.fromJson(m);
}

/// A prompt: one trigger plus up to two questions.
class ESPrompt {
  final String id;
  final ESTrigger trigger;
  final List<ESQuestion> questions;

  const ESPrompt({required this.id, required this.trigger, required this.questions});

  factory ESPrompt.fromJson(Map<String, dynamic> j) {
    final qs = <ESQuestion>[];
    final raw = j['questions'];
    if (raw is List) {
      for (final q in raw) {
        if (q is Map<String, dynamic>) qs.add(ESQuestion.fromJson(q));
      }
    }
    return ESPrompt(
      id: (j['id'] ?? 'prompt').toString(),
      trigger: ESTrigger.fromJson(
          j['trigger'] is Map<String, dynamic> ? j['trigger'] : {}),
      questions: qs.take(2).toList(), // enforce max two
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'trigger': trigger.toMap(),
        'questions': questions.map((q) => q.toMap()).toList(),
      };

  factory ESPrompt.fromMap(Map<String, dynamic> m) => ESPrompt(
        id: m['id'] as String,
        trigger: ESTrigger.fromMap(Map<String, dynamic>.from(m['trigger'])),
        questions: (m['questions'] as List)
            .map((e) => ESQuestion.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// The whole experience_sampling block.
class ESConfig {
  final bool enabled;
  final List<ESPrompt> prompts;

  const ESConfig({required this.enabled, required this.prompts});

  static ESConfig? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final raw = j['prompts'];
    final prompts = <ESPrompt>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map<String, dynamic>) prompts.add(ESPrompt.fromJson(p));
      }
    }
    return ESConfig(enabled: j['enabled'] == true, prompts: prompts);
  }

  Map<String, dynamic> toMap() =>
      {'enabled': enabled, 'prompts': prompts.map((p) => p.toMap()).toList()};

  static ESConfig? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return ESConfig(
      enabled: m['enabled'] as bool? ?? false,
      prompts: (m['prompts'] as List? ?? [])
          .map((e) => ESPrompt.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// One outgoing response row (answered or skipped), matching the server's
/// ESResponse model.
class ESResponseRecord {
  final String promptId;
  final String questionId;
  final String triggerType;
  final String zoneMarker;
  final String status; // answered | skipped
  final String? answerText;
  final double? answerValue;
  final String triggeredUtc;
  final String timestampUtc;

  const ESResponseRecord({
    required this.promptId,
    required this.questionId,
    required this.triggerType,
    required this.zoneMarker,
    required this.status,
    this.answerText,
    this.answerValue,
    required this.triggeredUtc,
    required this.timestampUtc,
  });

  Map<String, dynamic> toJson() => {
        'prompt_id': promptId,
        'question_id': questionId,
        'trigger_type': triggerType,
        'zone_marker': zoneMarker,
        'status': status,
        'answer_text': answerText,
        'answer_value': answerValue,
        'triggered_utc': triggeredUtc,
        'timestamp_utc': timestampUtc,
      };
}
