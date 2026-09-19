import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ner_logistics/services/routing/osrm_client.dart';
import 'package:ner_logistics/services/routing/osrm_models.dart';

void main() {
  // Real response from router.project-osrm.org: GMC Guwahati → via → Dispur,
  // two legs (so it contains a mid-route arrive/depart pair).
  final viaFixture = File('test/fixtures/osrm_route_via.json').readAsStringSync();
  const pts = [LatLng(26.1545, 91.77), LatLng(26.14, 91.79), LatLng(26.125, 91.80)];

  test('parses a real multi-leg route and hides the via-point join', () async {
    final client = OsrmClient(
      baseUrl: 'http://osrm.test',
      httpClient: MockClient((_) async => http.Response(viaFixture, 200)),
    );
    final route = (await client.route(pts)).first;

    expect(route.distanceM, closeTo(7226, 1));
    expect(route.geometry.length, greaterThan(50));
    expect(route.steps.where((s) => s.type == 'arrive'), hasLength(1));
    expect(route.steps.last.type, 'arrive');
    expect(route.steps.where((s) => s.type == 'depart'), hasLength(1));
    expect(route.steps.first.instruction, 'Head out on GMC Link Road');
    // Step positions increase along the route.
    for (var i = 1; i < route.stepStartsM.length; i++) {
      expect(route.stepStartsM[i], greaterThanOrEqualTo(route.stepStartsM[i - 1]));
    }
    final next = route.nextStepAfter(0)!;
    expect(next.step.type, isNot('depart'));
    expect(next.inM, greaterThan(0));
  });

  test('builds the OSRM route URL (polyline6, steps, alternatives)', () async {
    late Uri seen;
    final client = OsrmClient(
      baseUrl: 'http://osrm.test/',
      httpClient: MockClient((req) async {
        seen = req.url;
        return http.Response(viaFixture, 200);
      }),
    );
    await client.route(pts, alternatives: 3);
    expect(seen.path, '/route/v1/driving/91.770000,26.154500;91.790000,26.140000;91.800000,26.125000');
    expect(seen.queryParameters['geometries'], 'polyline6');
    expect(seen.queryParameters['alternatives'], '3');
    expect(seen.queryParameters['overview'], 'full');
  });

  test('surfaces OSRM error codes', () async {
    final client = OsrmClient(
      baseUrl: 'http://osrm.test',
      httpClient: MockClient((_) async => http.Response(
          '{"code":"NoRoute","message":"Impossible route between points"}', 400)),
    );
    expect(
      () => client.route(pts),
      throwsA(isA<OsrmException>().having((e) => e.code, 'code', 'NoRoute')),
    );
  });

  test('times out as a network error', () async {
    final client = OsrmClient(
      baseUrl: 'http://osrm.test',
      timeout: const Duration(milliseconds: 50),
      httpClient: MockClient((_) => Completer<http.Response>().future),
    );
    expect(
      () => client.route(pts),
      throwsA(isA<OsrmException>().having((e) => e.code, 'code', 'Network')),
    );
  });

  test('caches identical requests and spaces distinct ones', () async {
    var calls = 0;
    final client = OsrmClient(
      baseUrl: 'http://osrm.test',
      minInterval: const Duration(milliseconds: 150),
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(viaFixture, 200);
      }),
    );
    final sw = Stopwatch()..start();
    await client.route(pts);
    await client.route(pts);
    expect(calls, 1);
    await client.route(pts.reversed.toList());
    expect(calls, 2);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150));
  });

  test('the public demo server is throttled by default', () {
    expect(OsrmClient(baseUrl: 'https://router.project-osrm.org').minInterval,
        greaterThanOrEqualTo(const Duration(seconds: 1)));
    expect(OsrmClient(baseUrl: 'http://10.0.2.2:5000').minInterval, Duration.zero);
  });

  test('formats road refs and instructions', () {
    OsrmStep step(String type, {String? modifier, String ref = '', String name = '', int? exit}) =>
        OsrmStep(
          type: type,
          modifier: modifier,
          ref: ref,
          name: name,
          distanceM: 0,
          durationS: 0,
          location: const LatLng(0, 0),
          exit: exit,
        );
    expect(step('turn', ref: 'NH6;AH1').road, 'NH-6');
    expect(step('turn', ref: 'SH 5').road, 'SH-5');
    expect(step('turn', modifier: 'slight right', ref: 'NH206').instruction,
        'Turn slight right onto NH-206');
    expect(step('roundabout', exit: 2, name: 'GS Road').instruction,
        'At the roundabout, take exit 2 onto GS Road');
    expect(step('new name', modifier: 'straight', ref: 'NH6').instruction, 'Continue onto NH-6');
    expect(step('turn', modifier: 'left').turnsRight, isFalse);
    expect(step('continue', modifier: 'uturn', ref: 'NH6').instruction, 'Make a U-turn onto NH-6');
  });
}
