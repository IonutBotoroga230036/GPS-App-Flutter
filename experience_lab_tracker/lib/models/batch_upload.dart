import 'sensor_points.dart';

/// The exact payload the server expects at POST /upload/ingest and
/// POST /upload/register_session. Field names must not change:
/// {project_id, participant_id, phone_uuid, device_model,
///  gps_data, accel_data, beacon_data}.
///
/// Beacons were dropped from this Flutter client, but we still send an empty
/// `beacon_data` array so the server's existing model parses unchanged.
class BatchUpload {
  final int projectId;
  final String participantId;
  final String phoneUuid;
  final String deviceModel;
  final List<GpsPoint> gpsData;
  final List<AccelPoint> accelData;

  const BatchUpload({
    required this.projectId,
    required this.participantId,
    required this.phoneUuid,
    required this.deviceModel,
    required this.gpsData,
    required this.accelData,
  });

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'participant_id': participantId,
        'phone_uuid': phoneUuid,
        'device_model': deviceModel,
        'gps_data': gpsData.map((g) => g.toJson()).toList(),
        'accel_data': accelData.map((a) => a.toJson()).toList(),
        'beacon_data': const <dynamic>[], // always empty in this client
      };

  /// An empty payload used by register_session to lock the participant ID.
  factory BatchUpload.empty({
    required int projectId,
    required String participantId,
    required String phoneUuid,
    required String deviceModel,
  }) =>
      BatchUpload(
        projectId: projectId,
        participantId: participantId,
        phoneUuid: phoneUuid,
        deviceModel: deviceModel,
        gpsData: const [],
        accelData: const [],
      );
}
