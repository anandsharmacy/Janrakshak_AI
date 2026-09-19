import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../mock_data/mock_route_scenarios.dart';
import 'geo_config.dart';
import 'gis/geoserver_client.dart';
import 'gis/spatial_analytics.dart';
import 'routing/closure_impact.dart';
import 'routing/osrm_client.dart';
import 'routing/route_planner.dart';
import 'routing/trip_plan.dart';

/// Riverpod wiring for the routing engine (OSRM) and GIS analytics
/// (GeoServer). Override [geoConfigProvider] in tests or flavours.
final geoConfigProvider =
    Provider<GeoConfig>((_) => const GeoConfig.fromEnvironment());

final osrmClientProvider = Provider<OsrmClient>((ref) {
  final cfg = ref.watch(geoConfigProvider);
  final client = OsrmClient(baseUrl: cfg.osrmUrl, profile: cfg.osrmProfile);
  ref.onDispose(client.close);
  return client;
});

final tripPlannerProvider =
    Provider<TripPlanner>((ref) => TripPlanner(ref.watch(osrmClientProvider)));

final geoServerClientProvider = Provider<GeoServerClient?>((ref) {
  final cfg = ref.watch(geoConfigProvider);
  if (!cfg.geoserverEnabled) return null;
  final client =
      GeoServerClient(baseUrl: cfg.geoserverUrl, workspace: cfg.geoserverWorkspace);
  ref.onDispose(client.close);
  return client;
});

final spatialAnalyticsProvider = Provider<SpatialAnalyticsService>((ref) {
  final gs = ref.watch(geoServerClientProvider);
  return SpatialAnalyticsService(
      remote: gs == null ? null : GeoServerSpatialAnalytics(gs));
});

// ── Trips ────────────────────────────────────────────────────────────────────

/// Field officer trip TRP-2291, routed live.
final fieldTripPlanProvider = FutureProvider<TripRoutePlan>(
    (ref) => ref.watch(tripPlannerProvider).plan(fieldTripScenario));

/// Safer route around the trip's hazard. Kicked off as soon as the plan is
/// known so it's usually ready by the time the officer asks for it.
final fieldTripDetourProvider = FutureProvider<TripDetourPlan>((ref) async {
  final plan = await ref.watch(fieldTripPlanProvider.future);
  return ref.watch(tripPlannerProvider).detour(plan);
});

/// Rider's active delivery ASN-4821, routed live.
final riderTripPlanProvider = FutureProvider<TripRoutePlan>(
    (ref) => ref.watch(tripPlannerProvider).plan(riderTripScenario));

/// Hazards on the rider's remaining route (GeoServer or local estimate).
/// `alongM` values are relative to the vehicle's current position.
final riderRouteHazardsProvider = FutureProvider<RouteHazardReport>((ref) async {
  // Snapshot first, so hazards show offline and before the live route lands.
  final TripRoutePlan plan = ref.watch(riderTripPlanProvider).valueOrNull ??
      TripSnapshots.riderPlan() ??
      await ref.watch(riderTripPlanProvider.future);
  return ref.watch(spatialAnalyticsProvider).hazardsAlong(plan.ahead);
});

/// Detour for the rider around a hazard [aheadM] metres ahead of the vehicle.
final riderDetourProvider =
    FutureProvider.autoDispose.family<DetourResult, double>((ref, aheadM) async {
  final plan = await ref.watch(riderTripPlanProvider.future);
  final at = plan.vehicleM + aheadM;
  return ref.watch(tripPlannerProvider).planner.avoid(
        from: plan.vehicle,
        to: plan.scenario.destination,
        hazard: plan.route.sliceM(at - 1000, at + 1000),
      );
});

// ── Analytics ────────────────────────────────────────────────────────────────

final regionalAnalyticsProvider = FutureProvider.autoDispose<RegionalAnalytics>(
    (ref) => ref.watch(spatialAnalyticsProvider).regional());

final locationInsightProvider = FutureProvider.autoDispose
    .family<LocationInsight, LatLng>(
        (ref, p) => ref.watch(spatialAnalyticsProvider).inspect(p));

final closureImpactProvider = FutureProvider.autoDispose
    .family<ClosureImpact, ClosureQuery>(
        (ref, q) => ClosureAnalyzer(ref.watch(osrmClientProvider)).analyze(q));
