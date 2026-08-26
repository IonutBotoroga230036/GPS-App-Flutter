// UPDATED: lib/main.dart
// Adds a global navigator key, notification init, and routing so a tapped
// prompt notification opens the QuestionScreen. Additions marked // + ES.

import 'dart:convert'; // + ES

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/project_provider.dart';
import 'providers/recording_provider.dart';
import 'screens/project_selection_screen.dart';
import 'screens/question_screen.dart'; // + ES
import 'services/background_service.dart';
import 'services/notification_service.dart'; // + ES

// + ES: global navigator key so we can push the question screen from a
// notification tap, which happens outside any widget's BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// + ES: guards against opening the same prompt twice.
String? _openPromptId;

void _routeToPrompt(String payload) {
  try {
    final ctx = Map<String, dynamic>.from(jsonDecode(payload));
    final promptId = ctx['promptId'] as String?;
    if (promptId == null) return;
    if (_openPromptId == promptId) return; // already showing this one
    _openPromptId = promptId;

    navigatorKey.currentState
        ?.push(MaterialPageRoute(
          builder: (_) => QuestionScreen(context: ctx),
        ))
        .then((_) => _openPromptId = null);
  } catch (_) {
    // malformed payload; ignore
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeBackgroundService();

  // + ES: set up notifications and route taps to the question screen.
  await NotificationService.initMainIsolate(onTapPayload: _routeToPrompt);

  // + ES: if a notification launched the app from cold, handle it after start.
  final launch = await NotificationService.launchPayload();

  runApp(const ExperienceLabApp());

  if (launch != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _routeToPrompt(launch));
  }
}

class ExperienceLabApp extends StatelessWidget {
  const ExperienceLabApp({super.key});

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
        navigatorKey: navigatorKey, // + ES
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        home: const ProjectSelectionScreen(),
      ),
    );
  }
}
