import 'package:latlong2/latlong.dart';

import '../../mock_data/models.dart';
import '../../shared/map/ner_geo.dart';
import '../geo/geo_math.dart';
import 'osrm_client.dart';
import 'route_planner.dart';

/// A convoy's current position and where it is heading.
class ConvoyTrip {
  final String vehicleId;
  final String routeId;
  final LatLng position;
  final String destinationLabel;
  final LatLng? destination;
  const ConvoyTrip({
    required this.vehicleId,
    required this.routeId,
    required this.position,
    required this.destinationLabel,
    this.destination,
  });

  /// Places each vehicle on its highway (as the maps do) and resolves the
  /// destination town.
  static List<ConvoyTrip> fromFleet(Iterable<FleetVehicle> fleet) {
    final byId = {for (final v in fleet) v.id: v};
    return [
      for (final m in NerGeo.vehicles(fleet))
        ConvoyTrip(
          vehicleId: m.id,
          routeId: NerGeo.routeIdOf(byId[m.id]!.route),
          position: m.point,
          destinationLabel: byId[m.id]!.destination,
          destination: NerGeo.town(byId[m.id]!.destination),
        ),
    ];
  }
}

/// Simulated closure of [routeId] at [closurePoint] (default: highway middle).
class ClosureQuery {
  final String routeId;
  final LatLng? closurePoint;
  final double halfLengthM;
  final List<ConvoyTrip> convoys;
  const ClosureQuery({
    required this.routeId,
    required this.convoys,
    this.closurePoint,
    this.halfLengthM = 3000,
  });

  @override
  bool operator ==(Object other) =>
      other is ClosureQuery &&
      other.routeId == routeId &&
      other.closurePoint == closurePoint &&
      other.halfLengthM == halfLengthM &&
      other.convoys.map((c) => c.vehicleId).join(',') ==
          convoys.map((c) => c.vehicleId).join(',');

  @override
  int get hashCode => Object.hash(
      routeId, closurePoint, halfLengthM, convoys.map((c) => c.vehicleId).join(','));
}

enum ConvoyOutcome { unaffected, rerouted, hold, noDestination }

class ConvoyDetour {
  final ConvoyTrip trip;
  final ConvoyOutcome outcome;
  final DetourResult? result;
  const ConvoyDetour(this.trip, this.outcome, [this.result]);
}

class ClosureImpact {
  final String routeId;
  final List<LatLng> closure;
  final List<ConvoyDetour> convoys;
  const ClosureImpact(this.routeId, this.closure, this.convoys);

  Iterable<ConvoyDetour> _where(ConvoyOutcome o) =>
      convoys.where((c) => c.outcome == o);
  int get rerouted => _where(ConvoyOutcome.rerouted).length;
  int get holding => _where(ConvoyOutcome.hold).length;
  int get affected => rerouted + holding;

  Duration get averageDelay {
    final r = _where(ConvoyOutcome.rerouted).toList();
    if (r.isEmpty) return Duration.zero;
    final s = r.fold<int>(0, (a, c) => a + c.result!.extraTime.inSeconds);
    return Duration(seconds: s ~/ r.length);
  }
}

/// Routes each convoy on the closed highway around the closure via OSRM.
class ClosureAnalyzer {
  final RoutePlanner planner;
  ClosureAnalyzer(OsrmClient osrm) : planner = RoutePlanner(osrm);

  Future<ClosureImpact> analyze(ClosureQuery q) async {
    final line = NerGeo.highway(q.routeId);
    if (line == null) return ClosureImpact(q.routeId, const [], const []);
    final cum = GeoMath.cumulativeM(line);
    final centreM = q.closurePoint == null
        ? cum.last / 2
        : GeoMath.project(line, q.closurePoint!, cum).alongM;
    final closure =
        GeoMath.sliceM(line, centreM - q.halfLengthM, centreM + q.halfLengthM, cum);

    final out = <ConvoyDetour>[];
    // Sequential on purpose: the OSRM client rate-limits anyway.
    for (final c in q.convoys.where((c) => c.routeId == q.routeId)) {
      if (c.destination == null) {
        out.add(ConvoyDetour(c, ConvoyOutcome.noDestination));
        continue;
      }
      final r = await planner.avoid(from: c.position, to: c.destination!, hazard: closure);
      out.add(ConvoyDetour(
        c,
        r.baselineClear
            ? ConvoyOutcome.unaffected
            : r.found
                ? ConvoyOutcome.rerouted
                : ConvoyOutcome.hold,
        r,
      ));
    }
    return ClosureImpact(q.routeId, closure, out);
  }
}
