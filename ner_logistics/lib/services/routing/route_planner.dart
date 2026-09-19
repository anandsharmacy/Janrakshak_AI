import 'package:latlong2/latlong.dart';

import '../geo/geo_math.dart';
import 'osrm_client.dart';
import 'osrm_models.dart';

/// Result of asking for a route that avoids a hazard / closure.
class DetourResult {
  /// Fastest route between the same points ignoring the hazard.
  final OsrmRoute baseline;

  /// Safest acceptable route, or null when the road network offers no way
  /// around the hazard (common on single-corridor hill highways).
  final OsrmRoute? detour;

  /// Closest approach of [detour] to the hazard, in metres.
  final double clearanceM;

  /// Road the detour mainly uses that the baseline doesn't (e.g. `SH-5`).
  final String? via;

  /// True when the baseline itself never enters the hazard buffer.
  final bool baselineClear;

  const DetourResult({
    required this.baseline,
    this.detour,
    this.clearanceM = 0,
    this.via,
    this.baselineClear = false,
  });

  bool get found => detour != null;
  double get extraKm => found ? (detour!.distanceM - baseline.distanceM) / 1000 : 0;
  Duration get extraTime => found
      ? Duration(seconds: (detour!.durationS - baseline.durationS).round())
      : Duration.zero;
}

/// Hazard-aware planning on top of OSRM.
///
/// OSRM has no "avoid this area" option, so detours are found by
/// 1. asking for alternatives and keeping any that clear the hazard, then
/// 2. forcing a via-point at growing offsets either side of the hazard, and
///    if that fails, a pair of via-points flanking it on one side (a single
///    point lets the route cut back through the hazard's far end — common on
///    plains corridors with parallel roads),
/// keeping routes that clear the hazard without an excessive stretch.
class RoutePlanner {
  final OsrmClient osrm;
  RoutePlanner(this.osrm);

  Future<DetourResult> avoid({
    required LatLng from,
    required LatLng to,
    required List<LatLng> hazard,
    double clearanceM = 800,
    List<double> probeKm = const [5, 12, 25],
    double maxStretch = 3.0,
  }) async {
    final base = await osrm.route([from, to], alternatives: 3);
    final baseline = base.first;
    double clearance(OsrmRoute r) =>
        GeoMath.minDistanceBetweenM(hazard, r.geometry);

    if (clearance(baseline) >= clearanceM) {
      return DetourResult(
        baseline: baseline,
        detour: baseline,
        clearanceM: clearance(baseline),
        baselineClear: true,
      );
    }

    final candidates = <(OsrmRoute, double)>[
      for (final alt in base.skip(1))
        if (clearance(alt) >= clearanceM) (alt, clearance(alt)),
    ];

    if (candidates.isEmpty && hazard.isNotEmpty) {
      final centre = GeoMath.pointAtM(hazard, GeoMath.lengthM(hazard) / 2);
      final heading = hazard.length > 1
          ? GeoMath.bearingDeg(hazard.first, hazard.last)
          : GeoMath.bearingDeg(from, to);
      Future<void> tryVia(List<LatLng> via) async {
        final List<OsrmRoute> routes;
        try {
          routes = await osrm.route([from, ...via, to]);
        } on OsrmException catch (e) {
          if (e.code == 'Network') rethrow;
          return;
        }
        final r = routes.first;
        final c = clearance(r);
        if (c >= clearanceM && r.distanceM <= baseline.distanceM * maxStretch) {
          candidates.add((r, c));
        }
      }

      // Prefer the tightest offset that works; wider probes only add km.
      for (final km in probeKm) {
        final m = km * 1000;
        for (final side in const [90.0, -90.0]) {
          await tryVia([GeoMath.offsetM(centre, heading + side, m)]);
        }
        if (candidates.isNotEmpty) break;
        for (final side in const [90.0, -90.0]) {
          await tryVia([
            GeoMath.offsetM(GeoMath.offsetM(hazard.first, heading + 180, m / 2), heading + side, m),
            GeoMath.offsetM(GeoMath.offsetM(hazard.last, heading, m / 2), heading + side, m),
          ]);
        }
        if (candidates.isNotEmpty) break;
      }
    }

    if (candidates.isEmpty) return DetourResult(baseline: baseline);
    candidates.sort((a, b) => a.$1.durationS.compareTo(b.$1.durationS));
    final (best, c) = candidates.first;
    return DetourResult(
      baseline: baseline,
      detour: best,
      clearanceM: c,
      via: _distinctRoad(best, baseline),
    );
  }

  /// The road carrying the most detour distance that the baseline never uses.
  static String? _distinctRoad(OsrmRoute detour, OsrmRoute baseline) {
    final baseRoads = {for (final s in baseline.steps) s.road};
    final byRoad = <String, double>{};
    for (final s in detour.steps) {
      if (s.road.isEmpty || baseRoads.contains(s.road)) continue;
      byRoad[s.road] = (byRoad[s.road] ?? 0) + s.distanceM;
    }
    if (byRoad.isEmpty) return null;
    return (byRoad.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }
}
