import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../data/hazard.dart';

/// One maneuver: what to do at [at], then continue for [meters].
class RouteStep {
  const RouteStep(this.instruction, this.meters, this.at, this.type, this.modifier);
  final String instruction, type;
  final String? modifier;
  final double meters;
  final LatLng at;
}

class TripRoute {
  const TripRoute(this.points, this.km, this.minutes, {this.approximate = false, this.steps = const []});
  final List<LatLng> points;
  final List<RouteStep> steps;
  final double km, minutes;
  final bool approximate; // straight-line fallback when the routing service is unreachable
}

/// Driving route through [waypoints] via the public OSRM demo server.
// ponytail: demo server is rate-limited and has no SLA; self-host OSRM or use a paid router for production.
Future<TripRoute> fetchRoute(List<LatLng> waypoints) async {
  try {
    final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final res = await http
        .get(Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson&steps=true'))
        .timeout(const Duration(seconds: 12));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['code'] != 'Ok') throw StateError('OSRM ${j['code']}');
    final r = (j['routes'] as List).first as Map<String, dynamic>;
    final pts = [
      for (final c in (r['geometry']['coordinates'] as List)) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    return TripRoute(pts, (r['distance'] as num) / 1000, (r['duration'] as num) / 60, steps: parseSteps(r['legs'] as List));
  } catch (_) {
    return _straightLine(waypoints);
  }
}

/// Flattens OSRM legs into one step list. A diversion adds via-waypoints, which OSRM reports as arrive/depart pairs;
/// those are dropped so navigation never announces an arrival mid-route.
List<RouteStep> parseSteps(List legs) {
  final out = <RouteStep>[];
  for (var li = 0; li < legs.length; li++) {
    final steps = (legs[li] as Map<String, dynamic>)['steps'] as List;
    for (var si = 0; si < steps.length; si++) {
      final s = steps[si] as Map<String, dynamic>;
      final m = s['maneuver'] as Map<String, dynamic>;
      final type = m['type'] as String, mod = m['modifier'] as String?;
      final last = li == legs.length - 1 && si == steps.length - 1;
      if ((type == 'arrive' && !last) || (type == 'depart' && out.isNotEmpty)) continue;
      final loc = m['location'] as List;
      out.add(RouteStep(_say(type, mod, (s['name'] as String?) ?? '', m['exit'] as int?), (s['distance'] as num).toDouble(),
          LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()), type, mod));
    }
  }
  return out;
}

String _say(String type, String? mod, String name, int? exit) {
  final onto = name.isEmpty ? '' : ' onto $name';
  if (mod == 'uturn') return 'Make a U-turn$onto';
  final dir = mod ?? 'straight';
  return switch (type) {
    'depart' => name.isEmpty ? 'Start driving' : 'Start on $name',
    'arrive' => 'You have arrived',
    'turn' => dir == 'straight' ? 'Continue straight$onto' : 'Turn $dir$onto',
    'continue' => dir == 'straight' ? 'Continue straight' : 'Bear $dir$onto',
    'merge' => 'Merge$onto',
    'on ramp' => 'Take the ramp$onto',
    'off ramp' => 'Take the exit$onto',
    'fork' => 'Keep $dir at the fork$onto',
    'end of road' => 'Turn $dir$onto at the end of the road',
    'roundabout' || 'rotary' || 'roundabout turn' => exit == null ? 'Enter the roundabout' : 'At the roundabout, take exit $exit',
    'exit roundabout' || 'exit rotary' => 'Exit the roundabout$onto',
    _ => 'Continue$onto',
  };
}

TripRoute _straightLine(List<LatLng> wp) {
  final pts = <LatLng>[wp.first];
  var km = 0.0;
  for (var i = 1; i < wp.length; i++) {
    final a = wp[i - 1], b = wp[i];
    final d = distanceKm(a, b);
    km += d;
    final steps = (d / 2).ceil().clamp(1, 2000); // ~2 km spacing so hazard-radius checks still work
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      pts.add(LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t));
    }
  }
  return TripRoute(pts, km, km / 40 * 60, approximate: true, steps: [
    RouteStep('Head towards your destination', km * 1000, wp.first, 'depart', null),
    RouteStep('You have arrived', 0, wp.last, 'arrive', null),
  ]);
}
