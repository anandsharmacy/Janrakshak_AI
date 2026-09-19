import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../mock_data/mock_officers.dart';
import '../../mock_data/models.dart';
import '../../services/geo/geo_math.dart';
import '../../services/routing/trip_plan.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'ner_map.dart';

/// TripRouteMap — active trip map for the field officer RouteScreen.
///
/// Draws the OSRM route for TRP-2291 with the caution and high-risk stretches
/// placed on the real road, and the OSRM detour once rerouting starts.
/// Camera reframes on phase change.
class TripRouteMap extends StatelessWidget {
  final TripPhase phase;
  final bool postReroute;
  final bool riskUpgraded;
  final bool isOffline;
  final TripRoutePlan? plan;
  final TripDetourPlan? detour;

  const TripRouteMap({
    super.key,
    required this.phase,
    required this.postReroute,
    required this.riskUpgraded,
    required this.isOffline,
    required this.plan,
    this.detour,
  });

  @override
  Widget build(BuildContext context) {
    final p = plan;
    if (p == null) {
      return NerMap(
        fitPoints: const [LatLng(26.1445, 91.7362), LatLng(25.0455, 92.4205)],
        offlineMode: isOffline,
      );
    }

    final hazard = p.hazard;
    final caution = p.caution;
    final d = detour?.route;
    final following = phase == TripPhase.active && postReroute && d != null;
    final rerouted = phase == TripPhase.rerouted && d != null;
    final hazardAhead = phase != TripPhase.active || riskUpgraded || postReroute;
    final vehicle = following ? detour!.vehicleAfter! : p.vehicle;

    final routes = <MapRoute>[
      MapRoute(points: p.travelled, tone: MapLineTone.travelled),
    ];
    final List<LatLng> fit;

    if (following || rerouted) {
      final via = detour!.result.via;
      routes.addAll([
        // Original road beyond the vehicle, now avoided.
        MapRoute(points: p.ahead, tone: MapLineTone.avoided),
        if (following)
          MapRoute(points: d.sliceM(0, detour!.advanceM), tone: MapLineTone.travelled),
        MapRoute(
          label: via,
          points: following ? d.sliceM(detour!.advanceM, d.geometryLengthM) : d.geometry,
          tone: MapLineTone.clear,
        ),
        if (rerouted && caution != null && caution.startM > p.vehicleM &&
            GeoMath.minDistanceBetweenM(p.line(caution), d.geometry) < 100)
          MapRoute(points: p.line(caution), tone: MapLineTone.caution),
      ]);
      fit = [vehicle, ...GeoMath.simplify(d.geometry, 500)];
    } else {
      final ahead = GeoMath.simplify(p.ahead, 500);
      routes.addAll([
        MapRoute(
          label: p.hazardRoad.isEmpty ? null : p.hazardRoad,
          points: p.ahead,
          tone: MapLineTone.clear,
        ),
        if (caution != null && caution.startM > p.vehicleM)
          MapRoute(points: p.line(caution), tone: MapLineTone.caution),
        if (hazard != null && hazardAhead)
          MapRoute(points: p.line(hazard), tone: MapLineTone.critical),
        if (phase == TripPhase.calculating && d != null)
          MapRoute(points: d.geometry, tone: MapLineTone.candidate),
      ]);
      // Frame the next ~40 km around the hazard rather than the whole trip.
      fit = [
        vehicle,
        if (hazard != null) p.at(hazard.endM + 8000) else ...ahead,
        if (phase == TripPhase.calculating && d != null)
          ...GeoMath.simplify(d.geometry, 500),
      ];
    }

    return Stack(
      children: [
        Positioned.fill(
          child: NerMap(
            fitKey: (phase, postReroute, d != null),
            fitPoints: fit,
            // Leave room for the alert card (top) and legend (top-left).
            fitPadding: switch (phase) {
              TripPhase.interrupt => const EdgeInsets.fromLTRB(40, 230, 64, 32),
              TripPhase.rerouted => const EdgeInsets.fromLTRB(170, 32, 40, 32),
              _ => const EdgeInsets.fromLTRB(40, 40, 64, 40),
            },
            maxFitZoom: 13,
            offlineMode: isOffline,
            offlineRegionName: isOffline ? 'Ri Bhoi · NH-6 corridor' : null,
            showControls: phase != TripPhase.rerouted,
            routes: routes,
            zones: [
              if (hazard != null && hazardAhead && !following && !rerouted)
                MapZone(
                  center: p.at(hazard.midM),
                  radiusMeters: 1800,
                  kind: MapZoneKind.impact,
                  label: p.scenario.hazardLabel,
                ),
            ],
            incidents: [
              if (caution != null && !following && caution.startM > p.vehicleM)
                MapIncident(
                  id: 'trip-caution',
                  point: p.at(caution.midM),
                  severity: Priority.medium,
                  type: IncidentType.other,
                  label: '${caution.kmLabel} · ${p.scenario.cautionLabel}',
                ),
              if (hazard != null && hazardAhead)
                MapIncident(
                  id: 'trip-hazard',
                  point: p.at(hazard.midM),
                  severity: Priority.critical,
                  type: IncidentType.landslide,
                  label: '${p.hazardRoad} ${hazard.kmLabel} · '
                      '${p.scenario.hazardLabel}, ${p.scenario.hazardConfidence}% confidence',
                ),
            ],
            pois: [
              MapPoi(
                point: p.route.geometry.last,
                kind: MapPoiKind.destination,
                label: '${p.scenario.destinationLabel} · destination',
              ),
            ],
            vehicles: [
              MapVehicle(
                id: activeTrip.tripId,
                point: vehicle,
                risk: Priority.low,
                self: true,
                label: '${activeTrip.tripId} · ${activeTrip.consignment} · you are here',
              ),
            ],
          ),
        ),
        if (phase != TripPhase.interrupt)
          Positioned(
            left: 12,
            bottom: 12,
            child: RoutingSourceChip(live: p.live),
          ),
      ],
    );
  }
}

/// Small "where did this route come from" badge for routed maps.
class RoutingSourceChip extends StatelessWidget {
  final bool live;
  const RoutingSourceChip({super.key, required this.live});

  @override
  Widget build(BuildContext context) {
    final color = live ? AppColors.deepGreen700 : AppColors.saffronDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(live ? Icons.alt_route : Icons.save_outlined, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            live ? 'OSRM live route' : 'Saved route',
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
