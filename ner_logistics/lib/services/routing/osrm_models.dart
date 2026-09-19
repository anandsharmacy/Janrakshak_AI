import 'package:latlong2/latlong.dart';

import '../geo/geo_math.dart';

/// One OSRM route (all legs flattened). Parses both `polyline6` and GeoJSON
/// geometries, and serialises back to the OSRM response shape so baked
/// snapshots (see `tool/generate_geodata.dart`) round-trip through [fromJson].
class OsrmRoute {
  final List<LatLng> geometry;
  final double distanceM;
  final double durationS;
  final List<OsrmStep> steps;

  OsrmRoute({
    required this.geometry,
    required this.distanceM,
    required this.durationS,
    this.steps = const [],
  });

  late final List<double> cumulative = GeoMath.cumulativeM(geometry);

  /// Geometry length; can differ slightly from [distanceM] (road snapping).
  double get geometryLengthM => cumulative.isEmpty ? 0 : cumulative.last;

  /// Road metres per geometry metre (≈1; above 1 for simplified geometry).
  double get roadScale => geometryLengthM > 0 ? distanceM / geometryLengthM : 1;

  factory OsrmRoute.fromJson(Map<String, dynamic> json) {
    final g = json['geometry'];
    final List<LatLng> geometry;
    if (g is String) {
      geometry = GeoMath.decodePolyline(g);
    } else if (g is Map && g['coordinates'] is List) {
      geometry = [
        for (final c in g['coordinates'] as List)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
    } else {
      geometry = const [];
    }
    // Via-points split a route into legs; each leg ends in `arrive` and the
    // next starts with `depart`. Hide those joins so the driver is never told
    // to "arrive" mid-route (the depart step keeps its distance).
    final legs = json['legs'] as List? ?? const [];
    final steps = <OsrmStep>[];
    for (var l = 0; l < legs.length; l++) {
      for (final raw in ((legs[l] as Map)['steps'] as List? ?? const [])) {
        final s = OsrmStep.fromJson(raw as Map<String, dynamic>);
        if (s.type == 'arrive' && l < legs.length - 1) continue;
        steps.add(s.type == 'depart' && l > 0 ? s.asContinue() : s);
      }
    }
    return OsrmRoute(
      geometry: geometry,
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0,
      durationS: (json['duration'] as num?)?.toDouble() ?? 0,
      steps: steps,
    );
  }

  Map<String, dynamic> toJson({double simplifyToleranceM = 0}) => {
        'distance': distanceM,
        'duration': durationS,
        'geometry': GeoMath.encodePolyline(simplifyToleranceM > 0
            ? GeoMath.simplify(geometry, simplifyToleranceM)
            : geometry),
        'legs': [
          {'steps': [for (final s in steps) s.toJson()]},
        ],
      };

  LatLng pointAtM(double m) => GeoMath.pointAtM(geometry, m, cumulative);

  List<LatLng> sliceM(double fromM, double toM) =>
      GeoMath.sliceM(geometry, fromM, toM, cumulative);

  double alongM(LatLng p) => GeoMath.project(geometry, p, cumulative).alongM;

  /// Distance along the route at which each step's manoeuvre happens.
  late final List<double> stepStartsM = () {
    final out = <double>[];
    var acc = 0.0;
    for (final s in steps) {
      out.add(acc);
      acc += s.distanceM;
    }
    // OSRM step distances sum to [distanceM]; rescale onto the geometry so
    // step positions line up with [alongM] results.
    return [for (final m in out) m / roadScale];
  }();

  /// The next manoeuvre strictly ahead of [positionM] and how far away it is.
  ({OsrmStep step, double inM})? nextStepAfter(double positionM) {
    for (var i = 0; i < steps.length; i++) {
      if (stepStartsM[i] > positionM + 30 && steps[i].type != 'depart') {
        return (step: steps[i], inM: stepStartsM[i] - positionM);
      }
    }
    return null;
  }

  /// Road designation in force at [m] metres along the route (e.g. `NH-6`).
  String roadAtM(double m) {
    for (var i = steps.length - 1; i >= 0; i--) {
      if (stepStartsM[i] <= m && steps[i].road.isNotEmpty) return steps[i].road;
    }
    return '';
  }

  /// Seconds needed from [fromM] to the end, pro-rated by distance.
  double durationFromS(double fromM) {
    final total = geometryLengthM;
    if (total <= 0) return 0;
    return durationS * ((total - fromM).clamp(0, total) / total);
  }
}

class OsrmStep {
  /// OSRM manoeuvre type: depart, turn, new name, continue, merge, fork,
  /// on ramp, off ramp, end of road, roundabout, rotary, arrive, …
  final String type;
  final String? modifier;
  final String name;
  final String ref;
  final double distanceM;
  final double durationS;
  final LatLng location;
  final int? exit;

  const OsrmStep({
    required this.type,
    this.modifier,
    this.name = '',
    this.ref = '',
    required this.distanceM,
    required this.durationS,
    required this.location,
    this.exit,
  });

  factory OsrmStep.fromJson(Map<String, dynamic> json) {
    final m = json['maneuver'] as Map<String, dynamic>? ?? const {};
    final loc = m['location'] as List? ?? const [0, 0];
    return OsrmStep(
      type: m['type'] as String? ?? 'continue',
      modifier: m['modifier'] as String?,
      name: json['name'] as String? ?? '',
      ref: json['ref'] as String? ?? '',
      distanceM: (json['distance'] as num?)?.toDouble() ?? 0,
      durationS: (json['duration'] as num?)?.toDouble() ?? 0,
      location: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
      exit: (m['exit'] as num?)?.toInt(),
    );
  }

  OsrmStep asContinue() => OsrmStep(
        type: 'continue',
        modifier: 'straight',
        name: name,
        ref: ref,
        distanceM: distanceM,
        durationS: durationS,
        location: location,
      );

  Map<String, dynamic> toJson() => {
        'distance': distanceM,
        'duration': durationS,
        'name': name,
        'ref': ref,
        'maneuver': {
          'type': type,
          'modifier': ?modifier,
          'location': [location.longitude, location.latitude],
          'exit': ?exit,
        },
      };

  /// `NH6;AH1` → `NH-6`; falls back to the street name.
  String get road {
    final first = ref.split(';').first.trim();
    if (first.isNotEmpty) {
      return first.replaceAllMapped(
          RegExp(r'^([A-Za-z]+)\s*-?\s*(\d+\w*)$'), (m) => '${m[1]}-${m[2]}');
    }
    return name.trim();
  }

  bool get turnsRight => modifier?.contains('right') ?? false;

  /// Short English instruction, e.g. "Turn slight right onto NH-6".
  String get instruction {
    final r = road;
    final onto = r.isEmpty ? '' : ' onto $r';
    final dir = modifier == null || modifier == 'straight' ? '' : ' $modifier';
    if (modifier == 'uturn' && type != 'arrive') return 'Make a U-turn$onto';
    return switch (type) {
      'depart' => r.isEmpty ? 'Head out' : 'Head out on $r',
      'arrive' => 'Arrive at destination',
      'turn' || 'end of road' => 'Turn$dir$onto',
      'merge' => 'Merge$dir$onto',
      'on ramp' => 'Take the ramp$onto',
      'off ramp' => 'Take the exit$onto',
      'fork' => 'Keep${dir.isEmpty ? ' straight' : dir} at the fork$onto',
      'roundabout' || 'rotary' || 'roundabout turn' => exit == null
          ? 'Enter the roundabout'
          : 'At the roundabout, take exit $exit$onto',
      'exit roundabout' || 'exit rotary' => 'Exit the roundabout$onto',
      _ => 'Continue$dir$onto',
    };
  }
}
