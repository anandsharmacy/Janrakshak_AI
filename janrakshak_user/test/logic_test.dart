import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:janrakshak_user/data/feed.dart';
import 'package:janrakshak_user/data/hazard.dart';
import 'package:janrakshak_user/data/region_data.dart';
import 'package:janrakshak_user/data/taxonomy.dart';
import 'package:janrakshak_user/data/store.dart';
import 'package:janrakshak_user/features/report/report_service.dart';
import 'package:janrakshak_user/features/trip_planner/risk_layer.dart';
import 'package:janrakshak_user/features/trip_planner/routing.dart';
import 'package:latlong2/latlong.dart';

final sampleHazards = <Hazard>[
  Hazard(
      id: 'h1', type: 'Floods', severity: Severity.critical, state: 'Assam', district: 'Cachar',
      center: const LatLng(24.83, 92.78), radiusKm: 25, summary: 'Barak river above danger mark near Silchar.',
      source: ReportSource.fieldOfficer, at: DateTime.now().subtract(const Duration(hours: 2))),
  Hazard(
      id: 'h2', type: 'Landslides', severity: Severity.high, state: 'Meghalaya', district: 'East Khasi Hills',
      center: const LatLng(25.57, 91.88), radiusKm: 15, summary: 'Debris on the Shillong bypass.',
      source: ReportSource.community, at: DateTime.now().subtract(const Duration(hours: 5))),
  Hazard(
      id: 'h3', type: 'Alert', severity: Severity.moderate, state: 'Assam', district: 'Kamrup',
      summary: 'Advisory with no coordinates.', source: ReportSource.automated, at: DateTime.now()),
];

Future<void> openTestStore() async {
  Hive.init((await Directory.systemTemp.createTemp('jr_hive')).path);
  Store.pendingReports = await Hive.openBox<String>('pending_reports');
  Store.contacts = await Hive.openBox<String>('contacts_cache');
  Store.trips = await Hive.openBox<String>('recent_trips');
  Store.settings = await Hive.openBox<String>('settings');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('region data: 6 regions, 36 states/UTs, geocoder names map to canonical ones', () async {
    await RegionData.load();
    expect(RegionData.regionToStates.keys, unorderedEquals(RegionData.regionToIncidentTypes.keys));
    expect(RegionData.stateToDistricts.length, 36);
    expect(RegionData.regionToStates.values.expand((s) => s).length, 36);
    expect(RegionData.regionOf('Assam'), 'Northeast');
    expect(RegionData.regionOf('Puducherry'), 'South'); // UT folded into parent region
    expect(RegionData.matchState('NCT of Delhi'), 'Delhi');
    expect(RegionData.matchState('Jammu and Kashmir'), 'Jammu & Kashmir');
    expect(RegionData.matchDistrict('Assam', 'Cachar District'), 'Cachar');
    expect(RegionData.matchDistrict('Assam', 'Nowhere'), isNull);
  });

  test('risk layer flags a route through Cachar and the diversion clears the zone', () async {
    final risk = FeedRiskLayer(sampleHazards);
    const from = LatLng(24.83, 92.40), to = LatLng(24.83, 93.20); // passes through the Cachar flood zone
    final route = await fetchRoute([from, to]); // offline in tests -> straight-line fallback
    expect(route.approximate, isTrue);
    expect(await risk.intersectsRoute(route), isTrue);
    final avoid = await risk.segmentsToAvoid(route);
    expect(avoid.map((s) => s.hazard.district), contains('Cachar'));
    final diverted = await risk.getDivertedRoute(from, to, avoid);
    expect(diverted.points.any((p) => sampleHazards.first.covers(p)), isFalse);
    // a route far from any zone is untouched
    expect(await risk.intersectsRoute(await fetchRoute([const LatLng(12.9, 77.5), const LatLng(13.1, 77.7)])), isFalse);
  });

  test('offline queue: flushPending sends and clears every queued report, keeps failures', () async {
    await openTestStore();
    Report mk(String id) =>
        Report(id: id, state: 'Assam', district: 'Cachar', types: ['Floods'], description: 'Water rising fast');
    await Store.pendingReports.put('a', mk('a').toJsonString());
    await Store.pendingReports.put('b', mk('b').toJsonString());
    final sent = <String>[];
    expect(await flushPending(send: (r) async => r.id == 'b' ? throw StateError('offline') : sent.add(r.id)), isFalse);
    expect(sent, ['a']);
    expect(Store.pendingReports.keys, ['b']); // failed one stays queued for the next retry
    expect(await flushPending(send: (r) async => sent.add(r.id)), isTrue);
    expect(Store.pendingReports, isEmpty);
  });

  test('feed rows map to hazards: DB enums, coordinates optional, state spelling normalised', () async {
    await RegionData.load();
    final h = hazardFromRow({
      'id': 'incident:1', 'kind': 'incident', 'incident_type': 'flash_flood', 'severity': 'high',
      'state': 'Jammu and Kashmir', 'district': 'Srinagar', 'lat': 34.08, 'lng': 74.79, 'radius_km': 12.5,
      'summary': 'Flooding', 'source_kind': 'community', 'created_at': '2026-09-19T10:00:00Z',
    });
    expect(h.type, 'Floods');
    expect(h.severity, Severity.high);
    expect(h.state, 'Jammu & Kashmir');
    expect(h.source, ReportSource.community);
    expect(h.covers(const LatLng(34.08, 74.79)), isTrue);
    final bare = hazardFromRow({
      'id': 'alert:2', 'kind': 'alert', 'incident_type': null, 'severity': 'moderate', 'state': null, 'district': null,
      'lat': null, 'lng': null, 'radius_km': 10, 'summary': null, 'source_kind': 'automated',
      'created_at': '2026-09-19T10:00:00Z',
    });
    expect(bare.type, 'Alert');
    expect(bare.center, isNull);
    expect(bare.covers(const LatLng(0, 0)), isFalse);
  });
}
