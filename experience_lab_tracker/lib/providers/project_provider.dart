// UPDATED: lib/providers/project_provider.dart
// Stage 3 addition marked // + S3 : restoreFromSession rebuilds the selected
// project, config, and geojson from a saved session so the recording screen
// can be shown directly on reopen without re-picking a project.

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/project_config.dart';
import '../services/api_service.dart';

enum LoadState { idle, loading, ready, error }

class ProjectProvider extends ChangeNotifier {
  final ApiService _api;
  ProjectProvider({ApiService? api}) : _api = api ?? ApiService();

  LoadState state = LoadState.idle;
  String? error;

  List<Project> projects = [];
  Project? selected;
  ProjectConfig? config;
  String geojson = '';

  Future<void> loadProjects() async {
    state = LoadState.loading;
    error = null;
    notifyListeners();
    try {
      projects = await _api.fetchProjects();
      state = LoadState.ready;
    } catch (e) {
      error = 'Could not load projects: $e';
      state = LoadState.error;
    }
    notifyListeners();
  }

  Future<bool> selectProject(Project project) async {
    state = LoadState.loading;
    error = null;
    selected = project;
    notifyListeners();
    try {
      final settings = await _api.fetchProjectSettings(project.name);
      config = ProjectConfig.fromJson(settings);
      geojson = config!.geofencingEnabled
          ? await _api.fetchGeofence(project.name)
          : '';
      state = LoadState.ready;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Could not load project settings: $e';
      state = LoadState.error;
      notifyListeners();
      return false;
    }
  }

  /// + S3: rebuild state from a persisted session (no network needed).
  void restoreFromSession(Map<String, dynamic> session) {
    selected = Project(
      id: session['projectId'] as int,
      name: session['projectName'] as String? ?? 'Project',
    );
    config = ProjectConfig.fromMap(
        Map<String, dynamic>.from(session['config'] as Map));
    geojson = (session['geojson'] as String?) ?? '';
    state = LoadState.ready;
    notifyListeners();
  }

  void clearSelection() {
    selected = null;
    config = null;
    geojson = '';
    notifyListeners();
  }
}
