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
  List<String> _takenIds = [];
  bool _idLocked = false; // becomes true once recording starts

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pollNextId());
    _pollTimer = Timer.periodic(
      const Duration(seconds: AppConfig.participantPollSeconds),
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
        _takenIds = avail.takenIds;
        if (_idController.text.trim().isEmpty) {
          _idController.text = avail.nextAvailable;
        }
      });
    } catch (_) {
      // Non-fatal; the field is still editable.
    }
  }

  bool _isValidId(String id) {
    // Format: P followed by exactly 3 digits, e.g. P001.
    return RegExp(r'^P\d{3}$').hasMatch(id);
  }

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
    final project = projectProvider.selected!;
    final config = projectProvider.config!;

    final ok = await recording.startRecording(
      project: project,
      config: config,
      geojson: projectProvider.geojson,
      participantId: id,
    );

    if (!mounted) return;
    if (ok) {
      setState(() => _idLocked = true);
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
    final config = projectProvider.config;
    final isRecording = status.recording;

    return Scaffold(
      appBar: AppBar(
        title: Text(project?.name ?? 'Recording'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isRecording
              ? null // can't leave mid-recording
              : () {
                  projectProvider.clearSelection();
                  Navigator.of(context).pop();
                },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Participant ID
          TextField(
            controller: _idController,
            enabled: !isRecording,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(4),
              FilteringTextInputFormatter.allow(RegExp(r'[Pp0-9]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Participant ID',
              hintText: 'P001',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 8),
          if (_takenIds.isNotEmpty)
            Text('Taken: ${_takenIds.join(", ")}',
                style: Theme.of(context).textTheme.bodySmall),

          const SizedBox(height: 20),

          // Config summary
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

          // Start / Stop button
          SizedBox(
            height: 56,
            child: recording.busy
                ? const Center(child: CircularProgressIndicator())
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isRecording ? Colors.red : null,
                    ),
                    icon: Icon(isRecording ? Icons.stop : Icons.play_arrow),
                    label: Text(isRecording
                        ? 'Stop recording'
                        : 'Start recording'),
                    onPressed: isRecording ? _stop : _start,
                  ),
          ),

          const SizedBox(height: 24),

          // Live status panel
          _StatusPanel(status: status),
        ],
      ),
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
        : '—';

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
            _row(
                'Accuracy',
                status.acc == null
                    ? '—'
                    : '${status.acc!.toStringAsFixed(1)} m'),
            _row('Current zone', status.zone),
            _row('GPS buffered', '${status.gpsCount}'),
            _row('Accel buffered', '${status.accelCount}'),
            _row('Battery', '${status.battery}%'),
            _row('Last upload', status.lastUpload ?? '—'),
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
