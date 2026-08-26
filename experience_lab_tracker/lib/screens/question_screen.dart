// Experience sampling question screen.
// Place at: lib/screens/question_screen.dart
//
// Opened when a participant taps a prompt notification. It receives the prompt
// context (identity + questions) as a decoded map, walks the participant
// through up to two questions, then posts responses. Skipping (back button or
// the Skip button) posts a "skipped" record for each question and tells the
// background service the prompt is resolved so it is not double-logged.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/experience_sampling.dart';
import '../services/api_service.dart';
import '../utils/timestamp.dart';

class QuestionScreen extends StatefulWidget {
  /// The decoded notification payload (see background_service _fireEsPrompt).
  final Map<String, dynamic> context;
  const QuestionScreen({super.key, required this.context});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  final _api = ApiService();

  late final List<ESQuestion> _questions;
  int _index = 0;
  bool _submitting = false;

  // Collected answers keyed by question id.
  final Map<String, String?> _answerText = {};
  final Map<String, double?> _answerValue = {};

  // Working state for the current widget.
  double? _sliderVal;
  int? _scaleVal;
  final Set<String> _mcSelected = {};
  final TextEditingController _openCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rawQs = (widget.context['questions'] as List?) ?? [];
    _questions = rawQs
        .map((q) => ESQuestion.fromMap(Map<String, dynamic>.from(q)))
        .toList();
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    super.dispose();
  }

  ESQuestion get _current => _questions[_index];

  void _resetWorkingState() {
    _sliderVal = null;
    _scaleVal = null;
    _mcSelected.clear();
    _openCtrl.clear();
  }

  void _captureCurrentAnswer() {
    final q = _current;
    switch (q.type) {
      case 'scale':
        _answerValue[q.id] = _scaleVal?.toDouble();
        _answerText[q.id] = _scaleVal?.toString();
        break;
      case 'slider':
        final v = _sliderVal ?? q.min;
        _answerValue[q.id] = v;
        _answerText[q.id] = v.toString();
        break;
      case 'multiple_choice':
        _answerValue[q.id] = null;
        _answerText[q.id] = jsonEncode(_mcSelected.toList());
        break;
      case 'open':
        _answerValue[q.id] = null;
        _answerText[q.id] = _openCtrl.text.trim();
        break;
    }
  }

  bool get _hasAnswer {
    final q = _current;
    switch (q.type) {
      case 'scale':
        return _scaleVal != null;
      case 'slider':
        return true; // slider always has a value
      case 'multiple_choice':
        return _mcSelected.isNotEmpty;
      case 'open':
        return _openCtrl.text.trim().isNotEmpty;
    }
    return false;
  }

  Future<void> _next() async {
    _captureCurrentAnswer();
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _resetWorkingState();
      });
    } else {
      await _submit(status: 'answered');
    }
  }

  Future<void> _skip() async {
    await _submit(status: 'skipped');
  }

  Future<void> _submit({required String status}) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final ctx = widget.context;
    final triggeredUtc = ctx['triggeredUtc'] as String? ?? nowUtcTimestamp();
    final nowUtc = nowUtcTimestamp();

    final records = <ESResponseRecord>[];
    for (final q in _questions) {
      records.add(ESResponseRecord(
        promptId: ctx['promptId'] as String,
        questionId: q.id,
        triggerType: ctx['triggerType'] as String? ?? '',
        zoneMarker: ctx['zone'] as String? ?? 'None',
        status: status,
        answerText: status == 'answered' ? _answerText[q.id] : null,
        answerValue: status == 'answered' ? _answerValue[q.id] : null,
        triggeredUtc: triggeredUtc,
        timestampUtc: nowUtc,
      ));
    }

    // Close the screen FIRST so nothing below can trap the UI.
    if (mounted) Navigator.of(context).pop();

    // Post in the background (already confirmed working).
    _postInBackground(ctx, records);

    // Tell the service the prompt is resolved. Wrapped so any plugin
    // complaint can never freeze the screen.
    try {
      FlutterBackgroundService().invoke('promptResolved', {
        'promptId': ctx['promptId'],
      });
    } catch (_) {
      // non-fatal
    }
  }

  void _postInBackground(
      Map<String, dynamic> ctx, List<ESResponseRecord> records) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _api.uploadExperienceSampling(
          projectId: ctx['projectId'] as int,
          participantId: ctx['participantId'] as String,
          phoneUuid: ctx['phoneUuid'] as String,
          deviceModel: ctx['deviceModel'] as String,
          responses: records,
        );
        return; // success
      } catch (_) {
        // brief pause, then one retry
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions.')));
    }

    final q = _current;
    final isLast = _index == _questions.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && !_submitting) await _skip(); // back button = skip
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('Question ${_index + 1} of ${_questions.length}'),
          actions: [
            TextButton(
              onPressed: _submitting ? null : _skip,
              child: const Text('Skip'),
            ),
          ],
        ),
        body: _submitting
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(q.text,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 28),
                    Expanded(child: SingleChildScrollView(child: _buildInput(q))),
                    FilledButton(
                      onPressed: _hasAnswer ? _next : null,
                      child: Text(isLast ? 'Submit' : 'Next'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInput(ESQuestion q) {
    switch (q.type) {
      case 'scale':
        return _buildScale(q);
      case 'slider':
        return _buildSlider(q);
      case 'multiple_choice':
        return _buildMultipleChoice(q);
      case 'open':
        return _buildOpen(q);
    }
    return const SizedBox.shrink();
  }

  Widget _buildScale(ESQuestion q) {
    return Column(
      children: List.generate(q.points, (i) {
        final value = i + 1;
        final label = i < q.labels.length && q.labels[i].isNotEmpty
            ? '$value  -  ${q.labels[i]}'
            : '$value';
        return RadioListTile<int>(
          title: Text(label),
          value: value,
          groupValue: _scaleVal,
          onChanged: (v) => setState(() => _scaleVal = v),
        );
      }),
    );
  }

  Widget _buildSlider(ESQuestion q) {
    final val = _sliderVal ?? ((q.min + q.max) / 2);
    final divisions =
        q.step > 0 ? ((q.max - q.min) / q.step).round().clamp(1, 1000) : null;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(q.minLabel.isEmpty ? '${q.min}' : q.minLabel),
            Text(q.maxLabel.isEmpty ? '${q.max}' : q.maxLabel),
          ],
        ),
        Slider(
          min: q.min,
          max: q.max,
          divisions: divisions,
          value: val.clamp(q.min, q.max),
          label: val.toStringAsFixed(0),
          onChanged: (v) => setState(() => _sliderVal = v),
        ),
        Text('Selected: ${val.toStringAsFixed(0)}'),
      ],
    );
  }

  Widget _buildMultipleChoice(ESQuestion q) {
    return Column(
      children: q.options.map((opt) {
        if (q.multiple) {
          return CheckboxListTile(
            title: Text(opt),
            value: _mcSelected.contains(opt),
            onChanged: (checked) => setState(() {
              if (checked == true) {
                _mcSelected.add(opt);
              } else {
                _mcSelected.remove(opt);
              }
            }),
          );
        }
        return RadioListTile<String>(
          title: Text(opt),
          value: opt,
          groupValue: _mcSelected.isEmpty ? null : _mcSelected.first,
          onChanged: (v) => setState(() {
            _mcSelected
              ..clear()
              ..add(v!);
          }),
        );
      }).toList(),
    );
  }

  Widget _buildOpen(ESQuestion q) {
    return TextField(
      controller: _openCtrl,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: 'Type your answer',
      ),
      onChanged: (_) => setState(() {}), // refresh the Next button enabled state
    );
  }
}
