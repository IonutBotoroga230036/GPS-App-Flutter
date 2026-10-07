import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../providers/project_provider.dart';
import '../providers/recording_provider.dart';
import '../services/api_service.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final _idController = TextEditingController();
  final _api = ApiService();
  Timer? _pollTimer;
  String? _nextAvailable; // + only the next free P-number, not the full list
  List<String> _takenIds = []; // kept for local duplicate check, NOT displayed
  bool _idLocked = false;
  bool _cleanView = true; // + start on the clean branded screen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollNextId());
    _pollTimer = Timer.periodic(
      Duration(seconds: AppConfig.participantPollSeconds),
          (_) {
        if (!_idLocked) _pollNextId();
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _pollNextId() async {
    final project = context.read<ProjectProvider>().selected;
    if (project == null) return;
    try {
      final avail = await _api.fetchNextParticipant(project.name);
      if (!mounted) return;
      setState(() {
        _nextAvailable = avail.nextAvailable;
        _takenIds = avail.takenIds;
        if (_idController.text.trim().isEmpty) {
          _idController.text = avail.nextAvailable;
        }
      });
    } catch (_) {
      // Non-fatal; the field is still editable.
    }
  }

  bool _isValidId(String id) => RegExp(r'^P\d{3}$').hasMatch(id);

  Future<void> _start() async {
    final id = _idController.text.trim().toUpperCase();
    if (!_isValidId(id)) {
      _snack('Participant ID must look like P001 (P + 3 digits).');
      return;
    }
    if (_takenIds.contains(id)) {
      _snack('$id is already taken. Pick another.');
      return;
    }

    final projectProvider = context.read<ProjectProvider>();
    final recording = context.read<RecordingProvider>();
    final ok = await recording.startRecording(
      project: projectProvider.selected!,
      config: projectProvider.config!,
      geojson: projectProvider.geojson,
      participantId: id,
    );

    if (!mounted) return;
    if (ok) {
      setState(() {
        _idLocked = true;
        _cleanView = true; // drop into the clean screen once recording
      });
    } else {
      _snack(recording.actionError ?? 'Could not start recording.');
    }
  }

  Future<void> _stop() async {
    await context.read<RecordingProvider>().stopRecording();
    if (mounted) setState(() => _idLocked = false);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final recording = context.watch<RecordingProvider>();
    final status = recording.status;
    final project = projectProvider.selected;
    final isRecording = status.recording;

    return Scaffold(
      appBar: AppBar(
        title: Text(project?.name ?? 'Recording'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isRecording
              ? null
              : () {
            projectProvider.clearSelection();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          // + Toggle between the clean branded screen and the detail panel.
          IconButton(
            tooltip: _cleanView ? 'Show details' : 'Hide details',
            icon: Icon(_cleanView ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _cleanView = !_cleanView),
          ),
        ],
      ),
      body: _cleanView
          ? _buildCleanView(isRecording, status)
          : _buildDetailView(projectProvider, recording, status, isRecording),
    );
  }

  // ---------------------------------------------------------------- clean view
  Widget _buildCleanView(bool isRecording, RecordingStatus status) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // BUas logo. Falls back to text if the asset is not present yet.
          Image.asset(
            'assets/images/buas_logo.png',
            height: 90,
            errorBuilder: (_, __, ___) => Text(
              'BUas Experience Lab',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),

          if (isRecording) ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 56),
            const SizedBox(height: 16),
            Text('Recording in progress',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(_fmtElapsed(status.elapsedSec),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            Text(
              'Thank you for taking part in this research.\n'
                  'You can keep your phone in your pocket. '
                  'We will notify you if there is a question.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop recording'),
            ),
          ] else ...[
            Text('You are participant',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _idController.text.isEmpty
                  ? (_nextAvailable ?? '...')
                  : _idController.text,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start recording'),
                onPressed: context.watch<RecordingProvider>().busy ? null : _start,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _cleanView = false),
              child: const Text('Change participant ID'),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtElapsed(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }

  // --------------------------------------------------------------- detail view
  Widget _buildDetailView(ProjectProvider projectProvider,
      RecordingProvider recording, RecordingStatus status, bool isRecording) {
    final config = projectProvider.config;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _idController,
          enabled: !isRecording,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            LengthLimitingTextInputFormatter(4),
            FilteringTextInputFormatter.allow(RegExp(r'[Pp0-9]')),
          ],
          decoration: InputDecoration(
            labelText: 'Participant ID',
            // + show only the next available number, not the whole taken list
            helperText: _nextAvailable == null
                ? null
                : 'Next available: $_nextAvailable',
            hintText: 'P001',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 20),
        if (config != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Project configuration',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  _kv('GPS frequency', '${config.locationFrequencySec}s'),
                  _kv('Accelerometer',
                      config.gForceEnabled ? 'enabled' : 'disabled'),
                  _kv('Geofencing',
                      config.geofencingEnabled ? 'enabled' : 'disabled'),
                  _kv('Max duration', '${config.maxDurationHrs} h'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: recording.busy
              ? const Center(child: CircularProgressIndicator())
              : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : null,
            ),
            icon: Icon(isRecording ? Icons.stop : Icons.play_arrow),
            label:
            Text(isRecording ? 'Stop recording' : 'Start recording'),
            onPressed: isRecording ? _stop : _start,
          ),
        ),
        const SizedBox(height: 24),
        _StatusPanel(status: status),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(k), Text(v)],
    ),
  );
}

class _StatusPanel extends StatelessWidget {
  final RecordingStatus status;
  const _StatusPanel({required this.status});

  String _fmtElapsed(int s) {
    final h = (s ~/ 3600).toString().padLeft(2, '0');
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$h:$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final loc = (status.lat != null && status.lon != null)
        ? '${status.lat!.toStringAsFixed(5)}, ${status.lon!.toStringAsFixed(5)}'
        : '\u2014';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle,
                    size: 12,
                    color: status.recording ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  status.recording
                      ? (status.loggingEnabled
                      ? 'Recording'
                      : 'Recording (logging paused by zone)')
                      : 'Idle',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(_fmtElapsed(status.elapsedSec)),
              ],
            ),
            const Divider(),
            _row('Location', loc),
            _row('Accuracy',
                status.acc == null ? '\u2014' : '${status.acc!.toStringAsFixed(1)} m'),
            _row('Current zone', status.zone),
            _row('GPS buffered', '${status.gpsCount}'),
            _row('Accel buffered', '${status.accelCount}'),
            _row('Battery', '${status.battery}%'),
            _row('Last upload', status.lastUpload ?? '\u2014'),
            if (status.error != null) ...[
              const SizedBox(height: 8),
              Text(status.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: Colors.grey)),
        Flexible(child: Text(v, textAlign: TextAlign.right)),
      ],
    ),
  );
}