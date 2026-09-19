import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../geo/geo_math.dart';

/// Minimal GeoJSON model — enough for GeoServer WFS `application/json`.
/// Multi-geometries are flattened into [points] / [lines] / [polygons].
class GeoGeometry {
  final String type;
  final List<LatLng> points;
  final List<List<LatLng>> lines;

  /// Each polygon is a list of rings; ring 0 is the outer boundary.
  final List<List<List<LatLng>>> polygons;

  const GeoGeometry({
    required this.type,
    this.points = const [],
    this.lines = const [],
    this.polygons = const [],
  });

  static LatLng _pt(List c) =>
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
  static List<LatLng> _line(List c) => [for (final p in c) _pt(p as List)];
  static List<List<LatLng>> _poly(List c) => [for (final r in c) _line(r as List)];

  static GeoGeometry? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final type = j['type'] as String? ?? '';
    final c = j['coordinates'] as List? ?? const [];
    return switch (type) {
      'Point' => GeoGeometry(type: type, points: [_pt(c)]),
      'MultiPoint' => GeoGeometry(type: type, points: _line(c)),
      'LineString' => GeoGeometry(type: type, lines: [_line(c)]),
      'MultiLineString' => GeoGeometry(type: type, lines: _poly(c)),
      'Polygon' => GeoGeometry(type: type, polygons: [_poly(c)]),
      'MultiPolygon' =>
        GeoGeometry(type: type, polygons: [for (final p in c) _poly(p as List)]),
      _ => null,
    };
  }

  bool contains(LatLng p) =>
      polygons.any((poly) => poly.isNotEmpty && GeoMath.pointInRing(p, poly.first));

  /// Metres from [p] to this geometry (0 when inside a polygon).
  double distanceM(LatLng p) {
    if (contains(p)) return 0;
    var best = double.infinity;
    for (final q in points) {
      best = math.min(best, GeoMath.distanceM(p, q));
    }
    for (final l in [...lines, for (final poly in polygons) if (poly.isNotEmpty) poly.first]) {
      if (l.isNotEmpty) best = math.min(best, GeoMath.distanceToLineM(p, l));
    }
    return best;
  }

  /// Representative point (first point, line midpoint or ring average).
  LatLng? get anchor {
    if (points.isNotEmpty) return points.first;
    if (lines.isNotEmpty && lines.first.isNotEmpty) {
      return GeoMath.pointAtM(lines.first, GeoMath.lengthM(lines.first) / 2);
    }
    if (polygons.isNotEmpty && polygons.first.isNotEmpty) {
      final ring = polygons.first.first;
      final lat = ring.fold<double>(0, (s, p) => s + p.latitude) / ring.length;
      final lng = ring.fold<double>(0, (s, p) => s + p.longitude) / ring.length;
      return LatLng(lat, lng);
    }
    return null;
  }
}

class GeoFeature {
  final String? id;
  final Map<String, dynamic> properties;
  final GeoGeometry? geometry;
  const GeoFeature({this.id, this.properties = const {}, this.geometry});

  factory GeoFeature.fromJson(Map<String, dynamic> j) => GeoFeature(
        id: j['id']?.toString(),
        properties: (j['properties'] as Map?)?.cast<String, dynamic>() ?? const {},
        geometry: GeoGeometry.fromJson(j['geometry'] as Map<String, dynamic>?),
      );

  String str(String key, [String fallback = '']) =>
      properties[key]?.toString() ?? fallback;
  double num_(String key) => (properties[key] as num?)?.toDouble() ?? 0;
  int int_(String key) => (properties[key] as num?)?.toInt() ?? 0;
}

class GeoFeatureCollection {
  final List<GeoFeature> features;
  final int? numberMatched;
  const GeoFeatureCollection(this.features, {this.numberMatched});

  factory GeoFeatureCollection.fromJson(Map<String, dynamic> j) =>
      GeoFeatureCollection(
        [
          for (final f in (j['features'] as List? ?? const []))
            GeoFeature.fromJson(f as Map<String, dynamic>),
        ],
        numberMatched: (j['numberMatched'] ?? j['totalFeatures']) is num
            ? ((j['numberMatched'] ?? j['totalFeatures']) as num).toInt()
            : null,
      );
}
