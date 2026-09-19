import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/features/auth/application/auth_controller.dart';
import 'package:ner_logistics/features/auth/domain/auth_models.dart';
import 'package:ner_logistics/features/rider/logistics/application/rider_logistics_service.dart';
import 'package:ner_logistics/features/rider/logistics/data/mock_rider_data_source.dart';
import 'package:ner_logistics/features/rider/logistics/domain/rider.dart';
import 'package:ner_logistics/mock_data/models.dart';
import 'package:ner_logistics/services/geo/geo_math.dart';

const _lyngdoh = AuthUserProfile(
  userId: '00000000-0000-0000-0000-000000000004',
  email: 'p.lyngdoh@ner.gov.in',
  fullName: 'P. Lyngdoh',
  officerId: 'NER-RD-1184',
  role: AppRole.rider,
);

ProviderContainer _container({AuthUserProfile? profile = _lyngdoh}) {
  final c = ProviderContainer(overrides: [
    currentProfileProvider.overrideWithValue(profile),
    riderLogisticsAutoTickProvider.overrideWithValue(false),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<RiderLogisticsState> _loaded(ProviderContainer c) async {
  c.listen(riderLogisticsProvider, (_, _) {});
  for (var i = 0; i < 50 && c.read(riderLogisticsProvider).loading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(riderLogisticsProvider);
}

void main() {
  const source = MockRiderDataSource();

  group('mock data source', () {
    test('holds exactly the seven demo riders with correct identity fields', () async {
      final riders = await source.fetchRiders();
      expect(riders.map((r) => r.id), ['R001', 'R002', 'R003', 'R004', 'R005', 'R006', 'R007']);
      expect(riders.where((r) => r.isActive).length, 6);
      final r4 = riders.singleWhere((r) => r.id == 'R004');
      expect(r4.name, 'Kevichusa Angami');
      expect(r4.status, RiderStatus.inactive);
      expect(r4.district, 'Kohima');
      expect(riders.first.callsign, 'FALCON-1');
      expect(riders.last.callsign, 'FALCON-7');
      expect(riders[1].phone, '9876543211');
      expect(riders[4].rating, 4.9);
    });

    test('maps the seeded demo account to a dataset rider by officer id and by email', () async {
      final byOfficer = await source.riderForUser(userId: 'u', officerId: 'NER-RD-1184');
      final byEmail = await source.riderForUser(userId: 'u', email: 'P.Lyngdoh@ner.gov.in');
      expect(byOfficer?.id, 'R001');
      expect(byEmail?.id, 'R001');
    });

    test('an officer id that is already a dataset id wins', () async {
      final r = await source.riderForUser(userId: 'u', officerId: 'r006');
      expect(r?.id, 'R006');
    });

    test('unknown accounts resolve deterministically to an active rider', () async {
      final a = await source.riderForUser(userId: 'someone-else');
      final b = await source.riderForUser(userId: 'someone-else');
      expect(a, isNotNull);
      expect(a!.id, b!.id);
      expect(a.isActive, isTrue);
    });

    test('primary corridor is a multi-waypoint road, not a straight line', () async {
      final route = (await source.assignedRoute('R001'))!;
      expect(route.waypoints.length, greaterThanOrEqualTo(8));
      expect(route.origin, 'Guwahati');
      expect(route.destination, 'Shillong Depot');
      expect(route.id, 'NER-12');
      final straight = GeoMath.distanceM(route.start, route.end);
      expect(GeoMath.lengthM(route.waypoints), greaterThan(straight * 1.05));
      final incident = (await source.incidentOnRoute(route.id))!;
      expect(incident.point, route.waypoints[incident.waypointIndex]);
      expect(route.hasAlternate, isTrue);
      expect(route.alternate.last, route.end);
    });
  });

  group('rider logistics service', () {
    test('resolves the signed-in rider from the session and starts on the route', () async {
      final c = _container();
      final s = await _loaded(c);
      expect(s.rider?.id, 'R001');
      expect(s.rider?.name, 'Rohan Das');
      expect(s.rider?.callsign, 'FALCON-1');
      expect(s.rider?.routeStatus, RiderRouteStatus.open);
      expect(s.stage, RiderFlowStage.currentLocation);
      expect(s.rider?.routeProgress, closeTo(kDemoStartFraction, 0.01));
      // The rider sits on the corridor, not at a city centre.
      expect(GeoMath.distanceToLineM(s.rider!.point, s.route!.waypoints), lessThan(50));
    });

    test('no session means no rider and no hardcoded fallback', () async {
      final c = _container(profile: null);
      final s = c.read(riderLogisticsProvider);
      expect(s.loading, isFalse);
      expect(s.rider, isNull);
    });

    test('nearby riders are active, within radius, exclude self and never inactive', () async {
      final c = _container();
      final s = await _loaded(c);
      final ids = s.nearby.map((r) => r.id).toList();
      expect(ids, isNot(contains('R001')));
      expect(ids, isNot(contains('R004')));
      for (final r in s.nearby) {
        expect(r.isActive, isTrue);
        expect(GeoMath.distanceM(s.rider!.point, r.point), lessThanOrEqualTo(kNearbyRadiusM));
      }
      // Shillong (East Khasi Hills) is inside 50 km of the Nongpoh stretch.
      expect(ids, contains('R006'));
      // Dibrugarh, Aizawl, Imphal and Agartala are far outside the radius.
      expect(ids, isNot(contains('R002')));
      expect(ids, isNot(contains('R007')));
    });

    test('rider moves along the road each tick and ETA is derived from speed', () async {
      final c = _container();
      final before = await _loaded(c);
      final service = c.read(riderLogisticsProvider.notifier);
      service.tick();
      final after = c.read(riderLogisticsProvider);
      expect(after.alongM, greaterThan(before.alongM));
      expect(after.rider!.speed, greaterThan(0));
      expect(after.rider!.heading, isNotNull);
      final expectedEta = after.remainingM / (after.rider!.speed / 3.6);
      expect(after.rider!.eta!.inSeconds.toDouble(), closeTo(expectedEta, 2));
      expect(GeoMath.distanceToLineM(after.rider!.point, after.activePath), lessThan(50));
      // Nearby riders move on the same tick.
      final r6Before = before.nearby.singleWhere((r) => r.id == 'R006');
      final r6After = after.nearby.singleWhere((r) => r.id == 'R006');
      expect(r6After.point, isNot(equals(r6Before.point)));
    });

    test('incident triggers warning, alternate, and diversion only on confirmation', () async {
      final c = _container();
      await _loaded(c);
      final service = c.read(riderLogisticsProvider.notifier);

      // Drive until the incident is inside the trigger distance.
      var s = c.read(riderLogisticsProvider);
      var guard = 0;
      while (!s.incidentDetected && guard++ < 500) {
        service.tick();
        s = c.read(riderLogisticsProvider);
      }
      expect(s.incidentDetected, isTrue);
      expect(s.incidentAheadM, lessThanOrEqualTo(kIncidentTriggerDistanceM));
      expect(s.rider!.routeStatus, RiderRouteStatus.atRisk);
      expect(s.stage, RiderFlowStage.incidentDetected);
      expect(s.canConfirmDiversion, isFalse);

      service.tick();
      expect(c.read(riderLogisticsProvider).stage, RiderFlowStage.safetyWarning);
      service.tick();
      s = c.read(riderLogisticsProvider);
      expect(s.stage, RiderFlowStage.alternateReady);
      expect(s.canConfirmDiversion, isTrue);
      expect(s.offeredAlternate, isNotEmpty);
      expect(s.diverted, isFalse);

      // Declining keeps the road AT RISK; nothing switches on its own.
      service.dismissWarning();
      s = c.read(riderLogisticsProvider);
      expect(s.warningDismissed, isTrue);
      expect(s.warningActive, isTrue);
      expect(s.rider!.routeStatus, RiderRouteStatus.atRisk);

      // Driving on without confirming halts the rider before the blockage.
      for (var i = 0; i < 200; i++) {
        service.tick();
      }
      s = c.read(riderLogisticsProvider);
      expect(s.halted, isTrue);
      expect(s.rider!.routeStatus, RiderRouteStatus.blocked);
      expect(s.rider!.speed, 0);
      expect(s.diverted, isFalse);
      expect(s.incidentAheadM, closeTo(kHaltBeforeIncidentM, 5));

      // Explicit confirmation switches the road and the status.
      final etaBefore = c.read(riderLogisticsProvider).remainingM;
      service.confirmDiversion();
      s = c.read(riderLogisticsProvider);
      expect(s.diverted, isTrue);
      expect(s.stage, RiderFlowStage.diversionConfirmed);
      expect(s.rider!.routeStatus, RiderRouteStatus.diverted);
      expect(s.avoidedPath.length, greaterThanOrEqualTo(2));
      expect(s.activePath.last, s.route!.end);
      expect(s.remainingM, isNot(closeTo(etaBefore, 1)));
      // The blocked stretch stays on the avoided line; the driven road backs
      // away from the block (it starts at the halt point) and never returns.
      expect(GeoMath.distanceToLineM(s.incident!.point, s.avoidedPath), lessThan(50));
      final ahead = s.ahead;
      final beyondFirstKm = GeoMath.sliceM(ahead, 1000, GeoMath.lengthM(ahead));
      expect(GeoMath.distanceToLineM(s.incident!.point, beyondFirstKm), greaterThan(1000));
      // The rider drives back along the road to the branch, not cross-country.
      expect(GeoMath.distanceToLineM(ahead[1], s.route!.waypoints), lessThan(50));

      service.tick();
      expect(c.read(riderLogisticsProvider).stage, RiderFlowStage.routeSwitched);
      service.tick();
      s = c.read(riderLogisticsProvider);
      expect(s.stage, RiderFlowStage.continuing);
      expect(s.rider!.speed, greaterThan(0));
      expect(s.halted, isFalse);

      // And the rider reaches the depot on the new road.
      guard = 0;
      while (s.stage != RiderFlowStage.arrived && guard++ < 2000) {
        service.tick();
        s = c.read(riderLogisticsProvider);
      }
      expect(s.stage, RiderFlowStage.arrived);
      expect(s.rider!.routeProgress, 1);
      expect(s.rider!.point, s.route!.end);
    });
  });
}
