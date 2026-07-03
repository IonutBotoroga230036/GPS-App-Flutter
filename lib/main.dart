import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/project_provider.dart';
import 'providers/recording_provider.dart';
import 'screens/project_selection_screen.dart';
import 'services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register (but do not start) the background service.
  await initializeBackgroundService();

  runApp(const ExperienceLabApp());
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
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        home: const ProjectSelectionScreen(),
      ),
    );
  }
}
