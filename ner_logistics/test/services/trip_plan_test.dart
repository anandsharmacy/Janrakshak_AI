import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/mock_data/mock_fleet.dart';
import 'package:ner_logistics/services/geo/geo_math.dart';
import 'package:ner_logistics/services/routing/closure_impact.dart';
import 'package:ner_logistics/services/routing/trip_plan.dart';
import 'package:ner_logistics/shared/map/generated/geo_snapshot.g.dart';
import 'package:ner_logistics/shared/map/ner_geo.dart';

/// Checks the OSRM snapshot baked by tool/generate_geodata.dart.
void main() {
  test('snapshot is generated', () {
    expect(kSnapshotGeneratedAt, isNotEmpty);
    expect(kHighwayPolylines.keys, containsAll(NerGeo.highwayWaypoints.keys));
  });

  test('highways are road-snapped, not straight waypoint lines', () {
    final nh6 = NerGeo.highways['NH-6']!;
    expect(nh6.length, greaterThan(NerGeo.highwayWaypoints['NH-6']!.length * 20));
    expect(GeoMath.distanceM(nh6.first, NerGeo.shillong), lessThan(1500));
  });

  test('field trip places the hazard on the routed road', () {
    final plan = TripSnapshots.fieldPlan()!;
    expect(plan.live, isFalse);
    expect(plan.hazard!.kmLabel, 'Km 150–153');
    expect(plan.hazardRoad, 'NH-6');
    expect(plan.hazard!.startM - plan.vehicleM, closeTo(12000, 1));
    expect(plan.caution!.startM, greaterThan(plan.vehicleM));
    expect(plan.caution!.endM, lessThan(plan.hazard!.startM));
    expect(plan.remainingM, greaterThan(100000));
    final next = plan.nextStep!;
    expect(next.step.type, isNot('arrive'));
    expect(next.step.instruction, isNotEmpty);
  });

  test('field trip detour avoids the hazard', () {
    final plan = TripSnapshots.fieldPlan()!;
    final d = TripSnapshots.fieldDetour()!;
    expect(d.result.found, isTrue);
    expect(d.result.via, isNotNull);
    expect(d.result.extraKm, greaterThan(0));
    expect(
      GeoMath.minDistanceBetweenM(plan.line(plan.hazard!), d.route!.geometry),
      greaterThanOrEqualTo(800),
    );
    expect(d.route!.steps.where((s) => s.type == 'arrive'), hasLength(1));
    expect(d.vehicleAfter, isNotNull);
  });

  test('rider trip is placed mid-route', () {
    final plan = TripSnapshots.riderPlan()!;
    expect(plan.progress, closeTo(0.58, 0.001));
    expect(plan.remainingM / 1000, closeTo(18.6, 2));
  });

  test('formatting helpers', () {
    final now = DateTime(2026, 9, 12, 13, 0);
    expect(etaWindow(const Duration(hours: 1), now: now), '14:00 – 14:10');
    expect(etaClock(const Duration(minutes: 72), now: now), '14:12');
    expect(formatDistance(830), '850 m');
    expect(formatDistance(12400), '12.4 km');
    expect(formatDistance(118400), '118 km');
    expect(formatDuration(const Duration(minutes: 65)), '1 h 05 min');
  });

  test('closure queries compare by value (stable provider keys)', () {
    ClosureQuery q() => ClosureQuery(routeId: 'NH-29', convoys: ConvoyTrip.fromFleet(mockFleet));
    expect(q(), q());
    expect(q().hashCode, q().hashCode);
    final trips = ConvoyTrip.fromFleet(mockFleet);
    expect(trips.where((t) => t.routeId == 'NH-29'), isNotEmpty);
    expect(trips.every((t) => t.destination != null), isTrue);
  });
}
