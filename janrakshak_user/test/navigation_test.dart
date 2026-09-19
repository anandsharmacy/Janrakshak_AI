import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:janrakshak_user/data/offline_tiles.dart';
import 'package:janrakshak_user/data/providers.dart';
import 'package:janrakshak_user/features/trip_planner/navigation_controller.dart';
import 'package:janrakshak_user/features/trip_planner/navigation_screen.dart';
import 'package:janrakshak_user/features/trip_planner/route_progress.dart';
import 'package:janrakshak_user/features/trip_planner/routing.dart';
import 'package:janrakshak_user/features/trip_planner/trip_controller.dart';
import 'package:janrakshak_user/theme/app_theme.dart';
import 'package:latlong2/latlong.dart';

// East 0.1 deg (~10 km) then north 0.1 deg (~11 km); only three vertices, so vertices are ~10 km apart.
const a = LatLng(24.0, 92.0), b = LatLng(24.0, 92.1), c = LatLng(24.1, 92.1);
const steps = [
  RouteStep('Start on NH-27', 10170, a, 'depart', null),
  RouteStep('Turn left onto NH-6', 11100, b, 'turn', 'left'),
  RouteStep('You have arrived', 0, c, 'arrive', null),
];
final route = TripRoute(const [a, b, c], 21.3, 30, steps: steps);

class _FakeTrip extends TripController {
  @override
  TripState build() => TripState(from: const Place(pos: a, name: 'Start'), to: const Place(pos: c, name: 'Silchar'), original: route);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OSRM legs flatten to steps; via-waypoint arrive/depart are dropped', () {
    Map<String, dynamic> step(String type, String name, {String? mod, int? exit, num d = 100}) => {
          'name': name,
          'distance': d,
          'maneuver': {'type': type, 'modifier': ?mod, 'exit': ?exit, 'location': [92.0, 24.0]},
        };
    final out = parseSteps([
      {'steps': [step('depart', 'NH-27'), step('turn', 'NH-6', mod: 'right'), step('arrive', '')]}, // ends at the via point
      {'steps': [step('depart', ''), step('roundabout', '', exit: 2), step('turn', '', mod: 'uturn'), step('arrive', '')]},
    ]);
    expect(out.map((s) => s.instruction), ['Start on NH-27', 'Turn right onto NH-6', 'At the roundabout, take exit 2', 'Make a U-turn', 'You have arrived']);
  });

  test('tracker: midway on a 10 km segment is on-route with the turn ahead', () {
    final t = RouteTracker(route);
    final p = t.update(const LatLng(24.0, 92.05));
    expect(p.offRouteM, lessThan(30)); // nearest-vertex would say ~5 km off
    expect(p.next?.instruction, 'Turn left onto NH-6');
    expect(p.toNextM, closeTo(5085, 150));
    expect(p.remainingM, closeTo(5085 + 11100, 300));
    expect(p.arrived, isFalse);
  });

  test('tracker: off-route distance, then arrival at the end', () {
    final t = RouteTracker(route);
    expect(t.update(const LatLng(24.0045, 92.05)).offRouteM, closeTo(500, 40)); // ~500 m north of the road
    t.update(const LatLng(24.0, 92.099)); // just before the turn: turn is now imminent
    final near = t.update(const LatLng(24.0, 92.0995));
    expect(near.next?.type, 'turn');
    expect(near.toNextM, lessThan(100));
    final end = t.update(const LatLng(24.0999, 92.1));
    expect(end.arrived, isTrue);
    expect(end.next?.type, 'arrive');
  });

  test('tracker on a dense real-world style route (30 m vertices) measures distance, not zero', () {
    // ~45 km east along a road with a vertex every ~33 m, like OSRM output; rounding to whole km would make this 0 m.
    final pts = [for (var i = 0; i <= 1500; i++) LatLng(24.83, 92.78 + i * 0.000297)];
    final r = TripRoute(pts, 44.6, 60, steps: [
      RouteStep('Start on NH-27', 45035, pts.first, 'depart', null),
      RouteStep('You have arrived', 0, pts.last, 'arrive', null),
    ]);
    final t = RouteTracker(r);
    expect(t.cum.last, closeTo(45035, 100));
    final start = t.update(pts.first);
    expect(start.arrived, isFalse);
    expect(start.remainingM, closeTo(45035, 100));
    expect(start.next?.type, 'arrive');
    final mid = t.update(pts[750]);
    expect(mid.remainingM, closeTo(22517, 100));
    expect(mid.offRouteM, lessThan(5));
    expect(t.update(pts.last).arrived, isTrue);
  });

  test('real OSRM route (Silchar -> Hailakandi, 1,462 vertices): progress runs start to arrival in step order', () {
    final j = jsonDecode(File('test/fixtures/osrm_silchar_hailakandi.json').readAsStringSync()) as Map<String, dynamic>;
    final pts = [for (final c in j['geometry']['coordinates']) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())];
    final route = TripRoute(pts, j['distance'] / 1000, j['duration'] / 60, steps: parseSteps(j['legs'] as List));
    final t = RouteTracker(route);
    expect(t.cum.last, closeTo(j['distance'], 300)); // OSRM's own total
    final seen = <String>[];
    var lastRemaining = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final p = t.update(pts[i]);
      expect(p.offRouteM, lessThan(5), reason: 'on the road at vertex $i');
      expect(p.remainingM, lessThanOrEqualTo(lastRemaining + 1), reason: 'remaining distance never grows');
      lastRemaining = p.remainingM;
      final n = p.next?.instruction;
      if (n != null && (seen.isEmpty || seen.last != n)) seen.add(n);
    }
    expect(t.update(pts.first).arrived, isFalse);
    expect(seen.length, greaterThan(2)); // guidance moved through several maneuvers
    expect(seen.last, 'You have arrived');
    expect(t.update(pts.last).arrived, isTrue);
  });

  test('tile math and corridor cap', () {
    expect(tileOf(const LatLng(0, 0), 1), (1, 1));
    expect(tileOf(const LatLng(51.5, -0.12), 10), (511, 340)); // London
    const guwahatiToDelhi = [LatLng(26.14, 91.74), LatLng(28.61, 77.21)]; // sparse points, ~1,500 km
    final full = planCorridor(guwahatiToDelhi);
    expect(full.maxZoom, kPmtilesMaxZoom);
    expect(full.count, inInclusiveRange(500, 10000)); // even ~1,500 km is only about a thousand tiles at zoom 12
    final capped = planCorridor(guwahatiToDelhi, maxTiles: 600);
    expect(capped.count, lessThanOrEqualTo(600));
    expect(capped.maxZoom, lessThan(kPmtilesMaxZoom)); // over budget -> shallower map instead of a huge download
    final short = planCorridor(const [LatLng(24.83, 92.78), LatLng(24.86, 92.81)]);
    expect(short.maxZoom, kPmtilesMaxZoom);
  });

  testWidgets('navigation screen shows the next turn, updates with GPS, and announces arrival', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final gps = StreamController<LatLng>();
    addTearDown(gps.close);

    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        tripControllerProvider.overrideWith(_FakeTrip.new),
        userLocationProvider.overrideWith((_) => gps.stream),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const NavigationScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Waiting for GPS'), findsOneWidget);

    gps.add(const LatLng(24.0, 92.05));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Turn left onto NH-6'), findsOneWidget);
    expect(find.text('5.1 km'), findsWidgets);

    gps.add(const LatLng(24.0999, 92.1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Arrived'), findsWidgets);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
