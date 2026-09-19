import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:ner_logistics/mock_data/models.dart';
import 'package:ner_logistics/services/gis/geoserver_client.dart';
import 'package:ner_logistics/services/gis/spatial_analytics.dart';
import 'package:ner_logistics/services/routing/trip_plan.dart';
import 'package:ner_logistics/shared/map/map_models.dart';

void main() {
  // Real GeoServer responses (gs-stable.geo-solutions.it, gs:us_states).
  final statesJson = File('test/fixtures/geoserver_wfs_states.json').readAsStringSync();
  final exceptionXml = File('test/fixtures/geoserver_exception.xml').readAsStringSync();

  group('GeoServerClient', () {
    test('uses bbox with an explicit EPSG:4326 suffix and lon/lat output', () async {
      late Uri seen;
      final gs = GeoServerClient(
        baseUrl: 'http://gs.test/geoserver/',
        httpClient: MockClient((req) async {
          seen = req.url;
          return http.Response(statesJson, 200);
        }),
      );
      await gs.getFeatures('incidents',
          bbox: (west: 91.5, south: 25.0, east: 92.5, north: 26.5));
      expect(seen.path, '/geoserver/ner/ows');
      expect(seen.queryParameters['typeNames'], 'ner:incidents');
      expect(seen.queryParameters['bbox'], '91.5,25.0,92.5,26.5,EPSG:4326');
      expect(seen.queryParameters['srsName'], 'EPSG:4326');
      expect(seen.queryParameters.containsKey('CQL_FILTER'), isFalse);
      expect(gs.wmsUrl, 'http://gs.test/geoserver/ner/wms?');
    });

    test('parses a real WFS GeoJSON response', () async {
      final gs = GeoServerClient(
        baseUrl: 'http://gs.test/geoserver',
        httpClient: MockClient((_) async => http.Response(statesJson, 200)),
      );
      final fc = await gs.getFeatures('gs:us_states');
      expect(fc.numberMatched, 50);
      final illinois = fc.features.firstWhere((f) => f.str('STATE_NAME') == 'Illinois');
      expect(illinois.geometry!.type, 'MultiPolygon');
      expect(illinois.geometry!.contains(const LatLng(40.0, -89.0)), isTrue);
      expect(illinois.geometry!.contains(const LatLng(30.3, -97.7)), isFalse);
      expect(illinois.geometry!.distanceM(const LatLng(40.0, -89.0)), 0);
    });

    test('turns OWS exception reports into GeoServerException', () async {
      final gs = GeoServerClient(
        baseUrl: 'http://gs.test/geoserver',
        httpClient: MockClient((_) async => http.Response(exceptionXml, 400)),
      );
      expect(
        () => gs.getFeatures('incidents', cql: 'NOPE=1'),
        throwsA(isA<GeoServerException>()
            .having((e) => e.message, 'message', contains('Illegal property name'))),
      );
    });

    test('rejects bbox together with CQL (GeoServer would)', () {
      final gs = GeoServerClient(baseUrl: 'http://gs.test/geoserver');
      expect(
        () => gs.getFeatures('incidents',
            bbox: (west: 0, south: 0, east: 1, north: 1), cql: "status='x'"),
        throwsArgumentError,
      );
    });
  });

  group('GeoServerSpatialAnalytics', () {
    // Field names must match backend/geoserver/sql/03_analytics_views.sql.
    Map<String, dynamic> fc(List<Map<String, dynamic>> props) => {
          'type': 'FeatureCollection',
          'features': [
            for (final p in props)
              {
                'type': 'Feature',
                'properties': p,
                'geometry': {'type': 'Point', 'coordinates': [92.0, 25.5]},
              },
          ],
        };
    final views = {
      'ner:highway_risk_exposure': fc([
        {'highway_id': 'NH-6', 'total_km': 221.2, 'flood_km': 0.0, 'landslide_km': 18.5, 'incidents_2km': 1},
        {'highway_id': 'NH-27', 'total_km': 281.6, 'flood_km': 30.2, 'landslide_km': 0.0, 'incidents_2km': 2},
      ]),
      'ner:convoy_exposure': fc([
        {'vehicle_id': 'LG-115', 'route': 'NH-27', 'destination': 'Tezpur', 'risk': 'critical',
         'zone_kind': 'flood', 'zone_name': 'Barpeta floodplain', 'nearest_safe_zone': 'Guwahati relief camp', 'safe_zone_km': 71.3},
        {'vehicle_id': 'LG-134', 'route': 'NH-40', 'destination': 'Shillong', 'risk': 'low',
         'zone_kind': null, 'zone_name': null, 'nearest_safe_zone': 'Nongpoh staging area', 'safe_zone_km': 4.2},
      ]),
      'ner:area_incident_summary': fc([
        {'area': 'Barpeta', 'state': 'Assam', 'critical': 1, 'high': 0, 'medium': 0, 'low': 0, 'open_count': 1},
      ]),
    };

    test('maps the analytics views into models', () async {
      final gs = GeoServerClient(
        baseUrl: 'http://gs.test/geoserver',
        httpClient: MockClient((req) async =>
            http.Response(jsonEncode(views[req.url.queryParameters['typeNames']]), 200)),
      );
      final r = await GeoServerSpatialAnalytics(gs).regional();
      expect(r.source, AnalyticsSource.geoserver);
      expect(r.highways.first.id, 'NH-27'); // sorted by exposed km
      expect(r.highways.first.floodKm, 30.2);
      expect(r.convoys.where((c) => c.exposed).single.zoneKind, MapZoneKind.flood);
      expect(r.areas.single.critical, 1);
      expect(r.areas.single.open, 1);
    });

    test('service falls back to on-device estimates when GeoServer fails', () async {
      final gs = GeoServerClient(
        baseUrl: 'http://gs.test/geoserver',
        httpClient: MockClient((_) async => http.Response(exceptionXml, 400)),
      );
      final r = await SpatialAnalyticsService(remote: GeoServerSpatialAnalytics(gs)).regional();
      expect(r.source, AnalyticsSource.local);
      expect(r.note, contains('GeoServer unavailable'));
      expect(r.highways, isNotEmpty);
    });
  });

  group('LocalSpatialAnalytics', () {
    test('computes exposure from the demo zones', () async {
      final r = await const LocalSpatialAnalytics().regional();
      final nh6 = r.highways.firstWhere((h) => h.id == 'NH-6');
      expect(nh6.landslideKm, greaterThan(0)); // Jowai cut slopes sit on NH-6
      expect(nh6.totalKm, greaterThan(150));
      expect(r.areas.fold<int>(0, (s, a) => s + a.total), 7);
      expect(r.convoys, isNotEmpty);
    });

    test('finds the landslide zone on the rider\'s remaining route', () async {
      final plan = TripSnapshots.riderPlan()!;
      final report = await const LocalSpatialAnalytics().hazardsAlong(plan.ahead);
      final slope = report.hazards.firstWhere((h) => h.label == 'Umling–Nongpoh slope');
      expect(slope.kind, HazardKind.landslide);
      expect(slope.alongM, greaterThan(0));
      expect(slope.alongM, lessThan(plan.remainingM));
    });

    test('inspects a point inside a zone', () async {
      final i = await const LocalSpatialAnalytics().inspect(const LatLng(26.35, 91.0));
      expect(i.zones.map((z) => z.name), contains('Barpeta floodplain'));
      expect(i.incidents.first.severity, Priority.critical);
      expect(i.nearestSafeZone, isNotNull);
    });
  });
}
