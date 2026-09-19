import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/demo/demo_mode.dart';
import '../../mock_data/mock_route_scenarios.dart';
import '../../shared/map/generated/geo_snapshot.g.dart';
import 'osrm_client.dart';
import 'osrm_models.dart';
import 'route_planner.dart';

/// A stretch of a route, in metres along its drawn geometry.
class RouteSpan {
  final double startM;
  final double endM;

  /// Road metres per geometry metre. Simplified snapshot geometry is a
  /// little shorter than the road, so km markers use OSRM's distance.
  final double roadScale;
  const RouteSpan(this.startM, this.endM, {this.roadScale = 1});

  double get midM => (startM + endM) / 2;
  String get kmLabel => 'Km ${(startM * roadScale / 1000).round()}–'
      '${(endM * roadScale / 1000).round()}';
}

/// An OSRM route resolved against a [RouteScenario]: where the vehicle,
/// caution and hazard sit on the real road, and what's left to drive.
class TripRoutePlan {
  final RouteScenario scenario;
  final OsrmRoute route;

  /// True when fetched from the routing engine now; false for the baked
  /// offline snapshot.
  final bool live;
  final double vehicleM;
  final RouteSpan? hazard;
  final RouteSpan? caution;

  const TripRoutePlan._({
    required this.scenario,
    required this.route,
    required this.live,
    required this.vehicleM,
    this.hazard,
    this.caution,
  });

  factory TripRoutePlan.fromRoute(RouteScenario s, OsrmRoute route,
      {required bool live}) {
    final length = route.geometryLengthM;
    RouteSpan? span(LatLng? p, double half) {
      if (p == null) return null;
      final m = route.alongM(p);
      return RouteSpan(math.max(0, m - half), math.min(length, m + half),
          roadScale: route.roadScale);
    }

    final hazard = span(s.hazardPoint, s.hazardHalfSpanM);
    return TripRoutePlan._(
      scenario: s,
      route: route,
      live: live,
      hazard: hazard,
      caution: span(s.cautionPoint, s.cautionHalfSpanM),
      vehicleM: hazard != null
          ? math.max(0, hazard.startM - s.vehicleBeforeHazardM)
          : length * s.vehicleFraction,
    );
  }

  LatLng get vehicle => route.pointAtM(vehicleM);
  double get lengthM => route.geometryLengthM;
  /// Road metres still to drive (OSRM distance, not polyline length).
  double get remainingM => math.max(0, lengthM - vehicleM) * route.roadScale;

  /// Road metres between two positions along the geometry.
  double roadDistance(double fromM, double toM) => (toM - fromM) * route.roadScale;
  Duration get remaining => Duration(seconds: route.durationFromS(vehicleM).round());
  double get progress => lengthM == 0 ? 0 : vehicleM / lengthM;

  List<LatLng> get travelled => route.sliceM(0, vehicleM);
  List<LatLng> get ahead => route.sliceM(vehicleM, lengthM);
  List<LatLng> line(RouteSpan s) => route.sliceM(s.startM, s.endM);
  LatLng at(double m) => route.pointAtM(m);

  /// Road designation at the hazard, e.g. `NH-6`.
  String get hazardRoad => hazard == null ? '' : route.roadAtM(hazard!.midM);
  String get cautionRoad => caution == null ? '' : route.roadAtM(caution!.midM);

  ({OsrmStep step, double inM})? get nextStep => route.nextStepAfter(vehicleM);
}

/// The reroute around a plan's hazard, plus where the vehicle is once it
/// has started following it.
class TripDetourPlan {
  final DetourResult result;
  final bool live;
  final double advanceM;
  const TripDetourPlan(this.result, {required this.live, this.advanceM = 0});

  OsrmRoute? get route => result.detour;
  LatLng? get vehicleAfter => route?.pointAtM(advanceM);
  double get remainingAfterM => route == null
      ? 0
      : math.max(0, route!.geometryLengthM - advanceM) * route!.roadScale;
  Duration get remainingAfter => route == null
      ? Duration.zero
      : Duration(seconds: route!.durationFromS(advanceM).round());
  ({OsrmStep step, double inM})? get nextStepAfter =>
      route?.nextStepAfter(advanceM);
}

/// Live planning through OSRM.
class TripPlanner {
  final OsrmClient osrm;
  final RoutePlanner planner;
  TripPlanner(this.osrm) : planner = RoutePlanner(osrm);

  Future<TripRoutePlan> plan(RouteScenario s) async {
    final routes = await osrm.route(s.waypoints);
    return TripRoutePlan.fromRoute(s, routes.first, live: true);
  }

  Future<TripDetourPlan> detour(TripRoutePlan plan) async {
    final hazard = plan.hazard;
    if (hazard == null) {
      throw StateError('Scenario ${plan.scenario.id} has no hazard');
    }
    final result = await planner.avoid(
      from: plan.vehicle,
      to: plan.scenario.destination,
      hazard: plan.line(hazard),
    );
    return TripDetourPlan(result,
        live: true, advanceM: plan.scenario.postRerouteAdvanceM);
  }
}

/// Plans baked by `tool/generate_geodata.dart`, used offline and while the
/// live request is in flight. Null when the snapshot hasn't been generated.
class TripSnapshots {
  TripSnapshots._();

  static TripRoutePlan? fieldPlan() =>
      _plan(fieldTripScenario, kFieldTripRouteJson);
  static TripRoutePlan? riderPlan() =>
      _plan(riderTripScenario, kRiderTripRouteJson);

  static TripDetourPlan? fieldDetour() {
    if (!DemoMode.enabled || kFieldTripDetourJson.isEmpty) return null;
    return TripDetourPlan(
      detourFromJson(jsonDecode(kFieldTripDetourJson) as Map<String, dynamic>),
      live: false,
      advanceM: fieldTripScenario.postRerouteAdvanceM,
    );
  }

  static TripRoutePlan? _plan(RouteScenario s, String json) =>
      !DemoMode.enabled || json.isEmpty
      ? null
      : TripRoutePlan.fromRoute(
          s, OsrmRoute.fromJson(jsonDecode(json) as Map<String, dynamic>),
          live: false);
}

Map<String, dynamic> detourToJson(DetourResult r, {double simplifyM = 0}) => {
      'baseline': r.baseline.toJson(simplifyToleranceM: simplifyM),
      'detour': r.detour?.toJson(simplifyToleranceM: simplifyM),
      'clearance': r.clearanceM,
      'via': r.via,
      'baselineClear': r.baselineClear,
    };

DetourResult detourFromJson(Map<String, dynamic> j) => DetourResult(
      baseline: OsrmRoute.fromJson(j['baseline'] as Map<String, dynamic>),
      detour: j['detour'] == null
          ? null
          : OsrmRoute.fromJson(j['detour'] as Map<String, dynamic>),
      clearanceM: (j['clearance'] as num?)?.toDouble() ?? 0,
      via: j['via'] as String?,
      baselineClear: j['baselineClear'] as bool? ?? false,
    );

/// `14:20 – 14:50` style arrival window: OSRM time up to +20 % for trucks on
/// hill roads, rounded to 5 minutes.
String etaWindow(Duration remaining, {DateTime? now}) {
  final start = (now ?? DateTime.now()).add(remaining);
  final end = start.add(Duration(seconds: (remaining.inSeconds * 0.2).round()));
  String fmt(DateTime t) {
    final r = DateTime(t.year, t.month, t.day, t.hour, (t.minute / 5).round() * 5);
    return '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
  }

  return '${fmt(start)} – ${fmt(end)}';
}

/// Arrival clock time, e.g. `14:12`.
String etaClock(Duration remaining, {DateTime? now}) {
  final t = (now ?? DateTime.now()).add(remaining);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// `1 h 05 min` / `42 min`.
String formatDuration(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
}

/// `850 m` / `12.4 km` / `118 km`.
String formatDistance(double m) {
  if (m < 1000) return '${(m / 50).round() * 50} m';
  final km = m / 1000;
  return km < 20 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}
