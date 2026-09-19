import '../../../services/geo/geo_math.dart';
import '../../../services/routing/osrm_models.dart';
import '../../../services/routing/trip_plan.dart';

/// Everything the trip sheets print, derived from the OSRM plan and detour.
/// Falls back to the original demo copy when no route is available yet.
class TripCopy {
  final TripRoutePlan? plan;
  final TripDetourPlan? detour;

  /// True once the detour search has finished (found or not).
  final bool detourSettled;

  const TripCopy({this.plan, this.detour, this.detourSettled = false});

  RouteSpan? get _hazard => plan?.hazard;
  String get _dest => plan?.scenario.destinationLabel ?? 'Sonapur';

  bool get live => plan?.live ?? false;
  bool get hasDetour => detour?.result.found ?? false;
  bool get noDetour => detourSettled && detour != null && !hasDetour;

  String get sourceLabel => plan == null
      ? 'Route: demo'
      : plan!.live
          ? 'Route: OSRM live'
          : 'Route: saved offline copy';

  String get hazardSpan => _hazard == null
      ? 'NH-6 Km 31–34'
      : '${plan!.hazardRoad} ${_hazard!.kmLabel}'.trim();

  String get hazardTitle => '$hazardSpan is now high risk';

  String get hazardDetail {
    final p = plan, h = _hazard;
    if (p == null || h == null) {
      return 'Predicted landslide, 78% confidence · 5 km ahead, reaches you in 11 min.';
    }
    final ahead = p.roadDistance(p.vehicleM, h.startM);
    final mins = ((p.route.durationFromS(p.vehicleM) -
                p.route.durationFromS(h.startM)) /
            60)
        .round();
    return '${p.scenario.hazardLabel}, ${p.scenario.hazardConfidence}% confidence · '
        '${formatDistance(ahead)} ahead, reaches you in $mins min.';
  }

  String get cautionBanner {
    final c = plan?.caution;
    if (c == null) return 'Km 22–26 wet slope, reduce speed';
    return '${c.kmLabel} · ${plan!.scenario.cautionLabel}';
  }

  String get hazardBanner => '$hazardSpan flagged ahead · reroute advised';

  // ── Current route ─────────────────────────────────────────────────────────

  ({String km, String main, String sub, bool right}) get nextTurn {
    return _turn(plan?.nextStep) ??
        (km: '1.2 km', main: 'Left onto NH-6 spur', sub: 'at Km 26 junction', right: false);
  }

  String get eta => plan == null ? '14:20 – 14:50' : etaWindow(plan!.remaining);
  String get remaining => plan == null
      ? '48 km · $_dest'
      : '${formatDistance(plan!.remainingM)} · $_dest';

  // ── Detour ────────────────────────────────────────────────────────────────

  String get via => detour?.result.via ?? 'alternate road';

  String get candidate {
    if (!detourSettled) return 'Searching road network…';
    if (!hasDetour) return 'No road detour';
    return '$via, +${detour!.result.extraKm.toStringAsFixed(0)} km';
  }

  String get reroutedTitle => noDetour ? 'No safe road detour' : 'Rerouted via $via';

  String get reroutedBody {
    if (plan == null && detour == null) {
      return 'Avoids Km 31–34. Two lanes, PMGSY surface, clear at 09:40.';
    }
    if (noDetour) {
      return 'The road network has no way around $hazardSpan within 3× the '
          'distance. Hold at a safe point and await clearance.';
    }
    final c = detour!.result.clearanceM;
    return 'Avoids $hazardSpan with ${formatDistance(c)} clearance. '
        'Computed by OSRM on current road data.';
  }

  String get rerouteEta => hasDetour
      ? etaWindow(Duration(seconds: detour!.route!.durationS.round()))
      : eta;

  String get rerouteDelay => hasDetour
      ? '+${formatDuration(detour!.result.extraTime)} vs. original'
      : 'no alternative';

  /// Whether the detour still passes the earlier caution stretch.
  bool get cautionOnDetour =>
      hasDetour &&
      plan?.caution != null &&
      GeoMath.minDistanceBetweenM(
              plan!.line(plan!.caution!), detour!.route!.geometry) <
          100;

  String get rerouteRisk => cautionOnDetour ? 'Low · 1 caution' : 'Low';

  ({String km, String main, String sub, bool right})? get detourTurn {
    return _turn(detour?.route?.nextStepAfter(0));
  }

  /// Next manoeuvre once the vehicle is following the detour.
  ({String km, String main, String sub, bool right}) get followingTurn {
    return _turn(detour?.nextStepAfter) ??
        (km: '3.4 km', main: 'Right onto Lumshnong bypass', sub: 'then 21 km', right: true);
  }

  String get followingEta =>
      hasDetour ? etaWindow(detour!.remainingAfter) : '14:38 – 15:10';
  String get followingRemaining => hasDetour
      ? '${formatDistance(detour!.remainingAfterM)} · $_dest'
      : '40 km · $_dest';

  static ({String km, String main, String sub, bool right})? _turn(
      ({OsrmStep step, double inM})? n) {
    if (n == null) return null;
    return (
      km: formatDistance(n.inM),
      main: n.step.instruction,
      sub: 'then ${formatDistance(n.step.distanceM)}',
      right: n.step.turnsRight,
    );
  }
}
