// UPDATED: lib/main.dart
// Part 2 (notifications) + Stage 3 (resume routing). Stage 3 bits marked // + S3.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/project_provider.dart';
import 'providers/recording_provider.dart';
import 'screens/project_selection_screen.dart';
import 'screens/question_screen.dart';
import 'screens/recording_screen.dart'; // + S3
import 'services/background_service.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

String? _openPromptId;

void _routeToPrompt(String payload) {
  try {
    final ctx = Map<String, dynamic>.from(jsonDecode(payload));
    final promptId = ctx['promptId'] as String?;
    if (promptId == null) return;
    if (_openPromptId == promptId) return;
    _openPromptId = promptId;

    navigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => QuestionScreen(context: ctx)))
        .then((_) => _openPromptId = null);
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeBackgroundService();
  await NotificationService.initMainIsolate(onTapPayload: _routeToPrompt);

  final launch = await NotificationService.launchPayload();

  // + S3: if a recording session was active, we will land on the recording
  //       screen instead of the project picker.
  final activeSession = await RecordingProvider.activeSession();

  runApp(ExperienceLabApp(hasActiveSession: activeSession != null));

  if (launch != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _routeToPrompt(launch));
  }
}

class ExperienceLabApp extends StatelessWidget {
  final bool hasActiveSession; // + S3
  const ExperienceLabApp({super.key, this.hasActiveSession = false});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => RecordingProvider()),
      ],
      child: MaterialApp(
        title: 'Experience Lab Tracker',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        // + S3: choose the landing screen based on whether a session is live.
        home: hasActiveSession
            ? const _ResumeGate()
            : const ProjectSelectionScreen(),
      ),
    );
  }
}

/// + S3: rebuilds provider state from the saved session, tells the service to
/// resume, and shows the recording screen. Runs once on launch when a session
/// was active.
class _ResumeGate extends StatefulWidget {
  const _ResumeGate();

  @override
  State<_ResumeGate> createState() => _ResumeGateState();
}

class _ResumeGateState extends State<_ResumeGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  Future<void> _resume() async {
    final recording = context.read<RecordingProvider>();
    final projects = context.read<ProjectProvider>();

    final session = await recording.resumeIfActive();
    if (!mounted) return;

    if (session == null) {
      // Nothing to resume after all; go to the normal picker.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProjectSelectionScreen()),
      );
      return;
    }

    projects.restoreFromSession(session);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RecordingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
