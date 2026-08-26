/// One GPS sample. The JSON keys MUST match what the FastAPI server reads:
/// {"lat", "lon", "acc", "zone", "time", "battery"}.
/// `zone` is the geofence zone name, or the literal string "None" when the
/// participant is outside all zones (the server converts "None" to SQL NULL).
class GpsPoint {
  final double lat;
  final double lon;
  final double acc;
  final String zone;
  final String time; // "yyyy-MM-dd HH:mm:ss.SSS" (UTC)
  final int battery;

  const GpsPoint({
    required this.lat,
    required this.lon,
    required this.acc,
    required this.zone,
    required this.time,
    required this.battery,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'acc': acc,
        'zone': zone,
        'time': time,
        'battery': battery,
      };
}

/// One accelerometer sample.
/// JSON keys: {"x", "y", "z", "zone", "time"}.
class AccelPoint {
  final double x;
  final double y;
  final double z;
  final String zone;
  final String time;

  const AccelPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.zone,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
        'zone': zone,
        'time': time,
      };
}
