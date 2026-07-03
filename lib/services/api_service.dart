import 'package:dio/dio.dart';

import '../config/constants.dart';
import '../models/batch_upload.dart';
import '../models/project.dart';

/// Result of querying the next available participant ID.
class ParticipantAvailability {
  final String nextAvailable;
  final List<String> takenIds;
  const ParticipantAvailability({
    required this.nextAvailable,
    required this.takenIds,
  });
}

/// Thin HTTP client over the FastAPI server. One method per endpoint.
/// Every method throws on failure so callers can show an error.
class ApiService {
  final Dio _dio;

  ApiService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.serverBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              headers: {'Content-Type': 'application/json'},
            ));

  /// GET /projects  ->  list of active projects.
  Future<List<Project>> fetchProjects() async {
    final resp = await _dio.get('/projects');
    final data = resp.data;
    final list = <Project>[];
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) list.add(Project.fromJson(item));
      }
    }
    return list;
  }

  /// GET /projects/{name}/settings  ->  raw config_json map.
  Future<Map<String, dynamic>> fetchProjectSettings(String projectName) async {
    final resp = await _dio.get('/projects/$projectName/settings');
    final data = resp.data;
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  /// GET /projects/{name}/geofence  ->  GeoJSON string (may be empty).
  Future<String> fetchGeofence(String projectName) async {
    try {
      final resp = await _dio.get(
        '/projects/$projectName/geofence',
        options: Options(responseType: ResponseType.plain),
      );
      return resp.data?.toString() ?? '';
    } on DioException catch (e) {
      // A project without a geofence may 404; treat that as "no geofence".
      if (e.response?.statusCode == 404) return '';
      rethrow;
    }
  }

  /// GET /projects/{name}/participants/next
  Future<ParticipantAvailability> fetchNextParticipant(
      String projectName) async {
    final resp = await _dio.get('/projects/$projectName/participants/next');
    final data = resp.data;
    String next = 'P001';
    final taken = <String>[];
    if (data is Map) {
      next = (data['next_available'] ?? 'P001').toString();
      final t = data['taken_ids'];
      if (t is List) {
        for (final id in t) {
          taken.add(id.toString());
        }
      }
    }
    return ParticipantAvailability(nextAvailable: next, takenIds: taken);
  }

  /// POST /upload/register_session  ->  locks the participant ID on the server.
  Future<void> registerSession(BatchUpload payload) async {
    await _dio.post('/upload/register_session', data: payload.toJson());
  }

  /// POST /upload/ingest  ->  the main data sink. Returns true on success.
  Future<void> ingest(BatchUpload payload) async {
    await _dio.post('/upload/ingest', data: payload.toJson());
  }
}
