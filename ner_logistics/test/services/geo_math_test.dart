import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ner_logistics/services/geo/geo_math.dart';

void main() {
  const a = LatLng(25.0, 92.0);
  const b = LatLng(25.0, 92.1); // ~10.1 km east
  const c = LatLng(25.1, 92.1);

  test('polyline6 round-trips', () {
    final pts = [a, b, c, const LatLng(-10.123456, 150.654321)];
    final decoded = GeoMath.decodePolyline(GeoMath.encodePolyline(pts));
    expect(decoded.length, pts.length);
    for (var i = 0; i < pts.length; i++) {
      expect(decoded[i].latitude, closeTo(pts[i].latitude, 1e-6));
      expect(decoded[i].longitude, closeTo(pts[i].longitude, 1e-6));
    }
  });

  test('distance, point-at and slice agree', () {
    final ab = GeoMath.distanceM(a, b);
    expect(ab, closeTo(10087, 30));
    final line = [a, b, c];
    final mid = GeoMath.pointAtM(line, ab / 2);
    expect(mid.longitude, closeTo(92.05, 1e-3));
    final slice = GeoMath.sliceM(line, ab / 2, ab + 1000);
    expect(GeoMath.lengthM(slice), closeTo(ab / 2 + 1000, 5));
  });

  test('project finds along-distance and perpendicular offset', () {
    final line = [a, b];
    final p = GeoMath.offsetM(GeoMath.pointAtM(line, 4000), 0, 500);
    final proj = GeoMath.project(line, p);
    expect(proj.alongM, closeTo(4000, 10));
    expect(proj.offsetM, closeTo(500, 5));
  });

  test('pointInRing and simplify', () {
    const ring = [a, b, c, LatLng(25.1, 92.0), a];
    expect(GeoMath.pointInRing(const LatLng(25.05, 92.05), ring), isTrue);
    expect(GeoMath.pointInRing(const LatLng(25.2, 92.05), ring), isFalse);

    final wiggly = [
      for (var i = 0; i <= 100; i++)
        LatLng(25.0 + (i.isEven ? 0 : 0.00001), 92.0 + i * 0.001),
    ];
    expect(GeoMath.simplify(wiggly, 10).length, 2);
  });

  test('bounds pads by metres', () {
    final box = GeoMath.bounds([a, c], padM: 1000);
    expect(box.south, lessThan(25.0));
    expect(box.north, greaterThan(25.1));
    expect(box.east - box.west, greaterThan(0.1));
  });
}
