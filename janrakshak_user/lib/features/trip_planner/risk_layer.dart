import 'package:latlong2/latlong.dart';

import '../../data/hazard.dart';
import '../../data/taxonomy.dart';
import 'routing.dart';

/// A stretch of a route that runs through a hazard zone.
class Segment {
  const Segment(this.points, this.hazard);
  final List<LatLng> points;
  final Hazard hazard;
}

/// Swap point for a real ML / satellite risk service.
/// Pipeline: fetchRoute -> intersectsRoute -> (true) segmentsToAvoid -> getDivertedRoute.
abstract class RiskLayer {
  Future<bool> intersectsRoute(TripRoute route);
  Future<List<Segment>> segmentsToAvoid(TripRoute route);
  Future<TripRoute> getDivertedRoute(LatLng origin, LatLng destination, List<Segment> avoid);
}

/// Treats live feed hazards rated High/Critical (with coordinates) as no-go zones.
class FeedRiskLayer implements RiskLayer {
  FeedRiskLayer(List<Hazard> hazards)
      : _zones = hazards.where((h) => h.center != null && _restricting.contains(h.severity)).toList();

  static const _restricting = {Severity.high, Severity.critical};
  final List<Hazard> _zones;

  @override
  Future<bool> intersectsRoute(TripRoute route) async => (await segmentsToAvoid(route)).isNotEmpty;

  @override
  Future<List<Segment>> segmentsToAvoid(TripRoute route) async {
    final out = <Segment>[];
    for (final h in _zones) {
      var run = <LatLng>[];
      for (final p in route.points) {
        if (h.covers(p)) {
          run.add(p);
        } else if (run.isNotEmpty) {
          out.add(Segment(run, h));
          run = [];
        }
      }
      if (run.isNotEmpty) out.add(Segment(run, h));
    }
    return out;
  }

  /// Routes via a waypoint pushed clear of each hazard; tries both sides, keeps whichever ends up least inside a zone.
  @override
  Future<TripRoute> getDivertedRoute(LatLng origin, LatLng destination, List<Segment> avoid) async {
    const geo = Distance(roundResult: false);
    final bearing = geo.bearing(origin, destination);
    final zones = {for (final s in avoid) s.hazard}.toList()
      ..sort((a, b) => distanceKm(origin, a.center!).compareTo(distanceKm(origin, b.center!)));

    TripRoute? best;
    var bestInside = 1 << 30;
    for (final side in const [90, -90]) {
      final via = [for (final h in zones) geo.offset(h.center!, h.radiusKm * 1600, bearing + side)];
      final r = await fetchRoute([origin, ...via, destination]);
      final inside = r.points.where((p) => zones.any((h) => h.covers(p))).length;
      if (inside < bestInside) (best, bestInside) = (r, inside);
      if (inside == 0) break;
    }
    return best!;
  }
}
