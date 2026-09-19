import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mock_data/models.dart';
import '../../services/geo_providers.dart';
import '../../services/gis/spatial_analytics.dart';
import '../../services/routing/route_planner.dart';
import '../../services/routing/trip_plan.dart';
import '../../shared/analytics/geo_analytics_widgets.dart';
import '../../shared/map/ner_map.dart';
import '../../shared/map/trip_route_map.dart';
import '../../shared/widgets/widgets.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// Rider's route plan: live OSRM when online, baked snapshot offline or
/// while the request is in flight.
TripRoutePlan? _riderPlan(WidgetRef ref, bool isOffline) => isOffline
    ? TripSnapshots.riderPlan()
    : ref.watch(riderTripPlanProvider).valueOrNull ?? TripSnapshots.riderPlan();

/// Active-trip map, next instruction and live ETA / distance for the rider.
class RiderRoutePanel extends ConsumerWidget {
  final DeliveryAssignment assignment;
  final bool isOffline;
  final String statusLabel;

  const RiderRoutePanel({
    super.key,
    required this.assignment,
    required this.isOffline,
    required this.statusLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = _riderPlan(ref, isOffline);
    final hazards = ref.watch(riderRouteHazardsProvider).valueOrNull?.hazards ?? const [];
    final next = plan?.nextStep;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 190,
            child: plan == null
                ? const ColoredBox(
                    color: AppColors.navyTint,
                    child: Center(child: CircularProgressIndicator(color: AppColors.navy900)),
                  )
                : Stack(children: [
                    Positioned.fill(
                      child: NerMap(
                        interactive: false,
                        offlineMode: isOffline,
                        fitPoints: [plan.vehicle, plan.route.geometry.last],
                        fitPadding: const EdgeInsets.all(24),
                        showRouteLabels: false,
                        routes: [
                          MapRoute(points: plan.travelled, tone: MapLineTone.travelled),
                          MapRoute(points: plan.ahead, tone: MapLineTone.clear),
                        ],
                        incidents: [
                          for (final h in hazards)
                            MapIncident(
                              id: 'hz-${h.alongM.round()}',
                              point: h.point,
                              severity: h.severity,
                              type: switch (h.kind) {
                                HazardKind.flood => IncidentType.flood,
                                HazardKind.landslide => IncidentType.landslide,
                                HazardKind.incident => IncidentType.other,
                              },
                              label: h.label,
                            ),
                        ],
                        pois: [
                          MapPoi(
                            point: plan.route.geometry.last,
                            kind: MapPoiKind.destination,
                            label: assignment.destination,
                          ),
                        ],
                        vehicles: [
                          MapVehicle(
                            id: assignment.vehicleId,
                            point: plan.vehicle,
                            risk: assignment.priority,
                            label: '${assignment.vehicleId} · you are here',
                            self: true,
                          ),
                        ],
                      ),
                    ),
                    Positioned(left: 8, top: 8, child: RoutingSourceChip(live: plan.live)),
                  ]),
          ),
        ),
        const SizedBox(height: 14),
        const Text('Next instruction'),
        const SizedBox(height: 4),
        Text(
          next == null
              ? 'Continue to ${assignment.destination}'
              : '${next.step.instruction} in ${formatDistance(next.inM)}',
          style: AppTextStyles.cardTitle,
        ),
        const SizedBox(height: 12),
        Row(children: [
          _Metric(
            label: 'ETA',
            value: plan == null ? assignment.eta : etaClock(plan.remaining),
          ),
          _Metric(
            label: 'Remaining',
            value: plan == null
                ? assignment.distanceRemaining
                : formatDistance(plan.remainingM),
          ),
          _Metric(label: 'Status', value: statusLabel),
        ]),
      ],
    );
  }
}

/// Hazards on the rider's remaining route with an on-demand OSRM detour.
class RiderRouteHazards extends ConsumerStatefulWidget {
  const RiderRouteHazards({super.key});

  @override
  ConsumerState<RiderRouteHazards> createState() => _RiderRouteHazardsState();
}

class _RiderRouteHazardsState extends ConsumerState<RiderRouteHazards> {
  /// Hazard (metres ahead) the rider asked to route around.
  double? _avoidAt;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(riderRouteHazardsProvider);
    final report = async.valueOrNull;
    if (report == null) {
      return async.hasError
          ? CardSurface(
              padding: const EdgeInsets.all(14),
              child: Text('Route hazards unavailable: ${async.error}',
                  style: AppTextStyles.bodySmall),
            )
          : const Center(child: CircularProgressIndicator(color: AppColors.navy900));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnalyticsSourceChip(source: report.source, note: report.note),
        const SizedBox(height: 10),
        if (report.hazards.isEmpty)
          const CardSurface(
            padding: EdgeInsets.all(14),
            leftAccentColor: AppColors.deepGreen700,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline, color: AppColors.deepGreen700),
              title: Text('No mapped hazards on the remaining route'),
              subtitle: Text('Checked against incidents and flood / landslide zones.'),
            ),
          ),
        for (final h in report.hazards) ...[
          _HazardCard(
            hazard: h,
            onAvoid: () => setState(() => _avoidAt = h.alongM),
            detour: _avoidAt == h.alongM ? ref.watch(riderDetourProvider(h.alongM)) : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _HazardCard extends StatelessWidget {
  final RouteHazard hazard;
  final VoidCallback onAvoid;
  final AsyncValue<DetourResult>? detour;
  const _HazardCard({required this.hazard, required this.onAvoid, this.detour});

  @override
  Widget build(BuildContext context) {
    final critical = hazard.severity == Priority.critical || hazard.kind == HazardKind.landslide;
    final color = critical ? AppColors.signalRed700 : AppColors.saffron600;
    final d = detour;
    return CardSurface(
      padding: const EdgeInsets.all(14),
      leftAccentColor: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            switch (hazard.kind) {
              HazardKind.flood => Icons.water_drop_outlined,
              HazardKind.landslide => Icons.landslide_outlined,
              HazardKind.incident => Icons.warning_amber_outlined,
            },
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hazard.label, style: AppTextStyles.bodySmallMedium),
              const SizedBox(height: 2),
              Text(
                '${formatDistance(hazard.alongM)} ahead · '
                '${hazard.kind == HazardKind.incident ? 'reported incident' : '${hazard.kind.name} risk zone'}',
                style: AppTextStyles.caption,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        if (d == null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAvoid,
              icon: const Icon(Icons.alt_route_outlined, size: 18),
              label: const Text('Find safe alternate'),
            ),
          )
        else
          d.when(
            loading: () => Text('Searching road network (OSRM)…', style: AppTextStyles.caption),
            error: (e, _) => Text('Routing unavailable: $e', style: AppTextStyles.caption),
            data: (r) => Text(
              r.baselineClear
                  ? 'Your current route already avoids this hazard.'
                  : r.found
                      ? 'Alternate: +${r.extraKm.toStringAsFixed(1)} km, '
                          '+${formatDuration(r.extraTime)}'
                          '${r.via == null ? '' : ' via ${r.via}'} · needs control-room approval.'
                      : 'No road detour exists here. Slow down and follow control-room instructions.',
              style: AppTextStyles.bodySmall,
            ),
          ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 3),
          Text(value, style: AppTextStyles.cardTitle, overflow: TextOverflow.ellipsis),
        ]),
      );
}
