import 'dart:convert';

/// A named polygon zone parsed from the project's GeoJSON.
/// Coordinates are stored as [longitude, latitude] pairs (GeoJSON order).
class GeoZone {
  final String name;
  final List<List<double>> polygon; // list of [lon, lat]
  final double area; // relative area, used to pick the innermost zone

  GeoZone({required this.name, required this.polygon})
      : area = _absPolygonArea(polygon);
}

/// Shoelace area (absolute). Computed on raw lon/lat degrees, which is fine
/// because we only ever COMPARE areas to each other, never report them.
double _absPolygonArea(List<List<double>> poly) {
  double sum = 0;
  final n = poly.length;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    sum += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1];
  }
  return sum.abs() / 2.0;
}

/// Parses a GeoJSON FeatureCollection into a list of named zones.
/// Zone name comes from feature.properties.name, falling back to "Zone_N".
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

/// Ray-casting point-in-polygon test. Polygon vertices are [lon, lat] pairs.
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

/// Returns the name of the zone that contains the point.
///
/// FIX FOR NESTED ZONES: when the point falls inside more than one polygon
/// (for example a small Zone_2 sitting inside a big boundary Zone_1), we return
/// the SMALLEST one, i.e. the most specific / innermost zone. This is what lets
/// a point-of-interest inside the overall boundary be detected instead of being
/// swallowed by the big zone. Returns null if the point is outside every zone.
String? zoneForPoint(double lat, double lon, List<GeoZone> zones) {
  GeoZone? best;
  for (final z in zones) {
    if (isPointInPolygon(lat, lon, z.polygon)) {
      if (best == null || z.area < best.area) {
        best = z;
      }
    }
  }
  return best?.name;
}