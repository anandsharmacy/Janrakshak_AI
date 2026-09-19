import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ner_logistics/services/geo/geo_math.dart';
import 'package:ner_logistics/services/routing/osrm_client.dart';
import 'package:ner_logistics/services/routing/route_planner.dart';

/// Fake OSRM: 2-point requests return the straight baseline; via-point
/// requests return a line through the via points, unless
/// [viaThroughHazard] forces every route back through the hazard.
OsrmClient fakeOsrm(List<LatLng> baseline,
    {bool viaThroughHazard = false, bool pairsOnly = false, List<int>? calls}) {
  String body(List<List<LatLng>> routes) => jsonEncode({
        'code': 'Ok',
        'routes': [
          for (final r in routes)
            {
              'distance': GeoMath.lengthM(r),
              'duration': GeoMath.lengthM(r) / 15,
              'geometry': GeoMath.encodePolyline(r),
              'legs': [
                {'steps': []},
              ],
            },
        ],
      });
  return OsrmClient(
    baseUrl: 'http://osrm.test',
    httpClient: MockClient((req) async {
      calls?.add(1);
      final coords = req.url.pathSegments.last.split(';').map((c) {
        final p = c.split(',').map(double.parse).toList();
        return LatLng(p[1], p[0]);
      }).toList();
      // pairsOnly: a single via-point route cuts back through the hazard.
      if (coords.length == 2 || viaThroughHazard || (pairsOnly && coords.length == 3)) {
        return http.Response(body([baseline]), 200);
      }
      return http.Response(body([coords]), 200);
    }),
  );
}

void main() {
  const from = LatLng(25.0, 92.0);
  const to = LatLng(25.0, 92.2);
  const baseline = [from, to];
  final hazard = [const LatLng(25.0, 92.095), const LatLng(25.0, 92.105)];

  test('finds a via-point detour that clears the hazard', () async {
    final calls = <int>[];
    final r = await RoutePlanner(fakeOsrm(baseline, calls: calls))
        .avoid(from: from, to: to, hazard: hazard);
    expect(r.found, isTrue);
    expect(r.baselineClear, isFalse);
    expect(r.clearanceM, greaterThanOrEqualTo(800));
    expect(r.extraKm, greaterThan(0));
    expect(r.extraTime, greaterThan(Duration.zero));
    // Baseline + both sides of the first (5 km) probe, then stop.
    expect(calls.length, 3);
  });

  test('reports no detour when every road passes the hazard', () async {
    final calls = <int>[];
    final r = await RoutePlanner(fakeOsrm(baseline, viaThroughHazard: true, calls: calls))
        .avoid(from: from, to: to, hazard: hazard);
    expect(r.found, isFalse);
    expect(r.extraKm, 0);
    // Baseline + 3 offsets × (2 single via-points + 2 flanking pairs).
    expect(calls.length, 1 + 12);
  });

  test('falls back to flanking via-point pairs (parallel road)', () async {
    final calls = <int>[];
    final r = await RoutePlanner(fakeOsrm(baseline, pairsOnly: true, calls: calls))
        .avoid(from: from, to: to, hazard: hazard);
    expect(r.found, isTrue);
    expect(r.clearanceM, greaterThanOrEqualTo(800));
    // Baseline + 5 km singles (2, fail) + 5 km pairs (2, succeed).
    expect(calls.length, 5);
  });

  test('keeps the baseline when it already avoids the hazard', () async {
    final far = [const LatLng(25.3, 92.1), const LatLng(25.31, 92.1)];
    final r = await RoutePlanner(fakeOsrm(baseline)).avoid(from: from, to: to, hazard: far);
    expect(r.baselineClear, isTrue);
    expect(r.found, isTrue);
    expect(r.extraKm, 0);
  });
}
