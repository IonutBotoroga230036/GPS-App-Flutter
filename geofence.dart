import 'dart:convert';

/// A named polygon zone parsed from the project's GeoJSON.
/// Coordinates are stored as [longitude, latitude] pairs (GeoJSON order).
class GeoZone {
  final String name;
  final List<List<double>> polygon; // list of [lon, lat]

  const GeoZone({required this.name, required this.polygon});
}

/// Parses a GeoJSON FeatureCollection (the same format the Streamlit
/// Geofence Builder produces) into a list of named zones.
///
/// Supports Polygon geometries. The zone name comes from
/// feature.properties.name, falling back to "Zone_N".
List<GeoZone> parseGeoJson(String geoJsonString) {
  final zones = <GeoZone>[];
  if (geoJsonString.trim().isEmpty) return zones;

  dynamic root;
  try {
    root = jsonDecode(geoJsonString);
  } catch (_) {
    return zones;
  }
  if (root is! Map) return zones;

  final features = root['features'];
  if (features is! List) return zones;

  var index = 0;
  for (final f in features) {
    index++;
    if (f is! Map) continue;
    final geometry = f['geometry'];
    final properties = f['properties'];
    if (geometry is! Map) continue;

    final type = geometry['type']?.toString();
    final coords = geometry['coordinates'];
    if (type != 'Polygon' || coords is! List || coords.isEmpty) continue;

    // A Polygon is a list of linear rings; the first ring is the outer
    // boundary. We ignore holes for this use case.
    final outerRing = coords.first;
    if (outerRing is! List) continue;

    final polygon = <List<double>>[];
    for (final pt in outerRing) {
      if (pt is List && pt.length >= 2) {
        final lon = (pt[0] as num).toDouble();
        final lat = (pt[1] as num).toDouble();
        polygon.add([lon, lat]);
      }
    }
    if (polygon.length < 3) continue;

    String name = 'Zone_$index';
    if (properties is Map && properties['name'] != null) {
      name = properties['name'].toString();
    }
    zones.add(GeoZone(name: name, polygon: polygon));
  }
  return zones;
}

/// Ray-casting point-in-polygon test. Returns true if (lat, lon) is inside
/// the polygon. Polygon vertices are [lon, lat] pairs.
///
/// This is the direct equivalent of the Android app's
/// GeofenceMath.isPointInPolygon().
bool isPointInPolygon(double lat, double lon, List<List<double>> polygon) {
  var inside = false;
  final n = polygon.length;
  var j = n - 1;
  for (var i = 0; i < n; i++) {
    final xi = polygon[i][0]; // lon
    final yi = polygon[i][1]; // lat
    final xj = polygon[j][0];
    final yj = polygon[j][1];

    final intersects = ((yi > lat) != (yj > lat)) &&
        (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
    j = i;
  }
  return inside;
}

/// Returns the name of the first zone that contains the point, or null if the
/// point is outside every zone.
String? zoneForPoint(double lat, double lon, List<GeoZone> zones) {
  for (final z in zones) {
    if (isPointInPolygon(lat, lon, z.polygon)) return z.name;
  }
  return null;
}
