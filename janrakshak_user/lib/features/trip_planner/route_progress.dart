import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../../data/hazard.dart';
import 'routing.dart';

class Progress {
  const Progress({required this.along, required this.offRouteM, required this.remainingM, required this.arrived, this.next, this.toNextM});
  final double along, offRouteM, remainingM; // metres
  final bool arrived;
  final RouteStep? next; // upcoming maneuver, null on the final approach
  final double? toNextM;
}

class _Hit {
  const _Hit(this.dist, this.along, this.index);
  final double dist, along;
  final int index;
}

/// Snaps GPS fixes onto a route and answers "how far to the next turn / the end, and am I still on it?".
/// Uses point-to-segment distance, not nearest vertex: OSRM vertices can be hundreds of metres apart on highways.
class RouteTracker {
  RouteTracker(this.route) {
    final pts = route.points;
    cum = List.filled(pts.length, 0.0);
    for (var i = 1; i < pts.length; i++) {
      cum[i] = cum[i - 1] + distanceKm(pts[i - 1], pts[i]) * 1000;
    }
    stepAlong = [for (final s in route.steps) _nearest(s.at, 0, pts.length - 1).along];
  }

  final TripRoute route;
  late final List<double> cum, stepAlong;
  int _last = 0, _step = 0;

  _Hit _nearest(LatLng p, int from, int to) {
    final pts = route.points;
    final cosLat = cos(p.latitude * pi / 180);
    _Hit? best;
    for (var i = from; i < to && i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      // local flat metres, origin at a
      final abx = (b.longitude - a.longitude) * 111320 * cosLat, aby = (b.latitude - a.latitude) * 110540;
      final apx = (p.longitude - a.longitude) * 111320 * cosLat, apy = (p.latitude - a.latitude) * 110540;
      final len2 = abx * abx + aby * aby;
      final t = len2 == 0 ? 0.0 : ((apx * abx + apy * aby) / len2).clamp(0.0, 1.0);
      final d = sqrt(pow(apx - t * abx, 2) + pow(apy - t * aby, 2));
      if (best == null || d < best.dist) best = _Hit(d, cum[i] + t * (cum[i + 1] - cum[i]), i);
    }
    return best ?? _Hit(double.infinity, 0, 0);
  }

  Progress update(LatLng p) {
    final n = route.points.length;
    var hit = _nearest(p, max(0, _last - 3), min(n - 1, _last + 300)); // local window first: cheap, and stable on loops
    if (hit.dist > 150) hit = _nearest(p, 0, n - 1);
    _last = hit.index;
    while (_step < stepAlong.length && stepAlong[_step] <= hit.along + 8) {
      _step++;
    }
    final remaining = cum.last - hit.along;
    final hasNext = _step < stepAlong.length;
    return Progress(
      along: hit.along,
      offRouteM: hit.dist,
      remainingM: remaining,
      arrived: remaining < 25 && hit.dist < 100,
      next: hasNext ? route.steps[_step] : null,
      toNextM: hasNext ? stepAlong[_step] - hit.along : null,
    );
  }
}
