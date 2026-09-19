import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ner_logistics/features/ml/data/ml_repository.dart';
import 'package:ner_logistics/features/ml/domain/ml_models.dart';
import 'package:ner_logistics/features/ml/presentation/ml_widgets.dart';
import 'package:ner_logistics/shared/widgets/ai_card.dart';

/// Fixtures are real RPC responses from the local Supabase stack
/// (replay of 5 Aug 2025), so these tests pin the server contract.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('RPC parsing', () {
    test('rider routes: every assigned route, with and without coverage', () {
      final r = RoutesRisk.fromJson(_fixture('ml_my_routes.json'));
      expect(r.meta.state, MlState.replay);
      expect(r.meta.scoreDate, DateTime(2025, 8, 5));
      expect(r.meta.modelVersion, 'final_v3');
      expect(r.routes.map((x) => x.shipmentNumber), ['LG-108', 'LG-131']);

      final outside = r.routes.first.risk;
      expect(outside.summary.band, MlBand.noCoverage);
      expect(outside.coverageFraction, 0);
      expect(outside.summary.worst, isNull);

      final nh10 = r.routes.last.risk;
      expect(nh10.summary.band, MlBand.high);
      expect(nh10.summary.alerts, 44);
      expect(nh10.summary.reviews, 131);
      expect(nh10.coverageFraction, closeTo(0.556, 0.001));
      expect(nh10.summary.worst!.tier, MlTier.humanReview);
      expect(nh10.summary.worst!.steep, isTrue);
      expect(nh10.segments, isNotEmpty);
      expect(nh10.meta.runId, r.meta.runId, reason: 'every route carries the run it came from');
    });

    test('officer top alerts', () {
      final t = TopAlerts.fromJson(_fixture('ml_top_alerts.json'));
      expect(t.scope, 'region');
      expect(t.rows, hasLength(3));
      expect(t.inTier, 1713);
      expect(t.rows.first.segment.tier, MlTier.alert);
      expect(t.rows.first.nearPlace, isNotNull);
      expect(t.rows.first.segment.riskPercentile, greaterThan(99.9));
    });

    test('unavailable run parses to a labelled empty state', () {
      final r = RouteRisk.fromJson({'state': 'unavailable', 'route_length_m': 1000});
      expect(r.meta.hasData, isFalse);
      expect(r.summary.band, MlBand.noCoverage);
      expect(mlStateLabel(r.meta), 'ML unavailable');
    });

    test('nextRiskAfter finds the first flagged segment ahead of the vehicle', () {
      final r = RouteRisk(
        meta: MlMeta.unavailable,
        summary: const RouteRiskSummary(matched: 3, alerts: 1, reviews: 2, band: MlBand.high),
        segments: const [
          MlSegment(segmentId: 'A', alongM: 1000, lat: 0, lon: 0, riskPercentile: 99, tier: MlTier.humanReview),
          MlSegment(segmentId: 'B', alongM: 5000, lat: 0, lon: 0, riskPercentile: 99.9, tier: MlTier.alert),
        ],
      );
      expect(r.nextRiskAfter(0)!.segmentId, 'A');
      expect(r.nextRiskAfter(1200)!.segmentId, 'B');
      expect(r.nextRiskAfter(6000), isNull);
    });
  });

  group('wording', () {
    test('topShare never rounds the riskiest roads to "0%" or "100%"', () {
      expect(topShare(99.9987), 'Top 0.01%');
      expect(topShare(99.5), 'Top 0.50%');
      expect(topShare(95), 'Top 5.0%');
      expect(topShare(40), 'Top 60%');
      expect(topShare(null), '—');
    });

    test('state labels say replay, live and stale plainly', () {
      final d = DateTime(2025, 8, 5);
      expect(mlStateLabel(MlMeta(state: MlState.replay, scoreDate: d)), 'Replay · rainfall of 5 Aug 2025');
      expect(mlStateLabel(MlMeta(state: MlState.live, scoreDate: d)), 'Live · 5 Aug 2025');
      expect(mlStateLabel(MlMeta(state: MlState.stale, scoreDate: d)), 'Stale · last 5 Aug 2025');
    });
  });

  group('line helpers', () {
    final line = [for (var i = 0; i < 5001; i++) LatLng(27 + i * 1e-4, 88 + i * 1e-4)];

    test('decimate keeps both ends and caps the size', () {
      final d = decimate(line, 2000);
      expect(d, hasLength(2000));
      expect(d.first, line.first);
      expect(d.last, line.last);
      expect(decimate(line.sublist(0, 10), 2000), hasLength(10));
    });

    test('GeoJSON is lon/lat order', () {
      final g = lineGeoJson([const LatLng(27.1, 88.5)]);
      expect(g['type'], 'LineString');
      expect(g['coordinates'], [
        [88.5, 27.1]
      ]);
    });

    test('lineKey is stable and distinguishes lines', () {
      expect(lineKey(line), lineKey(List.of(line)));
      expect(lineKey(line), isNot(lineKey(line.reversed.toList())));
    });

    test('offline errors fall back to cache; others do not', () {
      expect(MlRepository.isOffline(const SocketException('no route')), isTrue);
      expect(MlRepository.isOffline(Exception('permission denied')), isFalse);
    });
  });

  group('widgets', () {
    testWidgets('route tile explains out-of-coverage routes', (t) async {
      final r = RoutesRisk.fromJson(_fixture('ml_my_routes.json'));
      await t.pumpWidget(_wrap(MlRouteRiskTile(title: 'LG-108', risk: r.routes.first.risk)));
      expect(find.text('Outside model coverage'), findsOneWidget);
      expect(find.textContaining('Siliguri corridor'), findsOneWidget);
    });

    testWidgets('route tile shows counts and the model tag for covered routes', (t) async {
      final r = RoutesRisk.fromJson(_fixture('ml_my_routes.json'));
      await t.pumpWidget(_wrap(MlRouteRiskTile(title: 'LG-131', risk: r.routes.last.risk)));
      expect(find.text('High risk on route'), findsOneWidget);
      expect(find.text('ML · final_v3'), findsOneWidget);
      expect(find.text('44'), findsOneWidget);
      expect(find.text('131'), findsOneWidget);
      expect(find.textContaining('56%'), findsOneWidget);
    });

    testWidgets('cached answers say when they were saved', (t) async {
      final meta = MlMeta(state: MlState.replay, scoreDate: DateTime(2025, 8, 5));
      await t.pumpWidget(_wrap(MlStateChip(meta: meta, cachedAt: DateTime(2026, 9, 12, 9, 5))));
      expect(find.textContaining('Saved'), findsOneWidget);
      expect(find.textContaining('Replay · rainfall of 5 Aug 2025'), findsOneWidget);
    });

    testWidgets('demo AI cards say they are not model output', (t) async {
      await t.pumpWidget(_wrap(const AiCard(
          demo: true, kind: 'Demo scenario', confidence: 87, title: 'x', body: Text('y'))));
      expect(find.text('Illustrative demo content — not model output.'), findsOneWidget);
      expect(find.textContaining('confidence'), findsNothing);
    });
  });
}
