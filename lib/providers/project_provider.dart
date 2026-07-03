import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/project_config.dart';
import '../services/api_service.dart';

enum LoadState { idle, loading, ready, error }

/// Holds the list of projects, the selected project, and its fetched
/// configuration + geofence GeoJSON.
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

  /// Selects a project and downloads its settings + geofence.
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

  void clearSelection() {
    selected = null;
    config = null;
    geojson = '';
    notifyListeners();
  }
}
