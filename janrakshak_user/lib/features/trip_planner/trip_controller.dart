import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/feed.dart';
import '../../data/providers.dart';
import '../../data/taxonomy.dart';
import 'risk_layer.dart';
import 'routing.dart';
import 'trip_store.dart';

final riskLayerProvider = Provider<RiskLayer>((ref) => FeedRiskLayer(ref.watch(hazardsProvider)));

/// One check of a trip: getRoute -> riskLayer.intersectsRoute -> (true) riskLayer.getDivertedRoute.
class TripPlan {
  const TripPlan(this.original, this.diverted, this.avoid);
  final TripRoute original;
  final TripRoute? diverted;
  final List<Segment> avoid;
  TripRoute get chosen => diverted ?? original;
}

Future<TripPlan> planTrip(RiskLayer risk, LatLng from, LatLng to) async {
  final route = await fetchRoute([from, to]);
  if (!await risk.intersectsRoute(route)) return TripPlan(route, null, const []);
  final avoid = await risk.segmentsToAvoid(route);
  return TripPlan(route, await risk.getDivertedRoute(from, to, avoid), avoid);
}

/// Plain-language reason shown when a route was diverted.
String reasonFor(List<Segment> avoid) {
  final h = avoid.first.hazard;
  return '${h.type.toLowerCase()} reported near ${h.district}, ${h.state}; '
      '${avoid.any((s) => s.hazard.severity == Severity.critical) ? 'the affected road is restricted' : 'the affected road is at risk'}.';
}

class TripState {
  const TripState({
    this.from,
    this.to,
    this.loading = false,
    this.original,
    this.diverted,
    this.avoid = const [],
    this.error,
  });
  final Place? from, to;
  final bool loading;
  final TripRoute? original, diverted;
  final List<Segment> avoid;
  final String? error;

  bool get hasResult => original != null;
  TripRoute? get chosen => diverted ?? original;

  /// Diverted route still crosses a zone (no clean detour found).
  bool get stillRisky => diverted != null && diverted!.points.any((p) => avoid.any((s) => s.hazard.covers(p)));

  String? get reason => diverted == null ? null : reasonFor(avoid);

  TripState copyWith({Place? from, Place? to, bool? loading, TripRoute? Function()? original, TripRoute? Function()? diverted,
          List<Segment>? avoid, String? Function()? error}) =>
      TripState(
        from: from ?? this.from,
        to: to ?? this.to,
        loading: loading ?? this.loading,
        original: original != null ? original() : this.original,
        diverted: diverted != null ? diverted() : this.diverted,
        avoid: avoid ?? this.avoid,
        error: error != null ? error() : this.error,
      );
}

class TripController extends Notifier<TripState> {
  @override
  TripState build() => const TripState();

  void setFrom(Place p) => state = state.copyWith(from: p, original: () => null, diverted: () => null, avoid: const []);
  void setTo(Place p) => state = state.copyWith(to: p, original: () => null, diverted: () => null, avoid: const []);

  /// getRoute -> riskLayer.intersectsRoute -> (true) riskLayer.getDivertedRoute. Always evaluates against current risk data.
  Future<void> check({Place? from, Place? to}) async {
    final f = from ?? state.from, t = to ?? state.to;
    if (f == null || t == null) return;
    state = TripState(from: f, to: t, loading: true);
    try {
      final plan = await planTrip(ref.read(riskLayerProvider), f.pos, t.pos);
      state = TripState(from: f, to: t, original: plan.original, diverted: plan.diverted, avoid: plan.avoid);
      await saveTrip(f, t);
      // Keep "Active Trip Route" alerts in step with the latest check of the active trip.
      final active = ref.read(activeRouteProvider);
      final id = Trip.idOf(f, t);
      if (active?.tripId == id) await ref.read(activeRouteProvider.notifier).set(id, state.chosen!.points);
    } catch (e) {
      state = TripState(from: f, to: t, error: "Couldn't check this route: $e");
    }
  }
}

final tripControllerProvider = NotifierProvider<TripController, TripState>(TripController.new);
