import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../data/providers.dart';
import 'risk_layer.dart';
import 'route_progress.dart';
import 'routing.dart';
import 'trip_controller.dart';

/// Live GPS while navigating. Overridable in tests.
final userLocationProvider = StreamProvider.autoDispose<LatLng>((ref) async* {
  final first = await currentPosition(); // also triggers the permission prompt
  if (first == null) return;
  yield LatLng(first.latitude, first.longitude);
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
  ).map((p) => LatLng(p.latitude, p.longitude));
});

const offRouteMetres = 60.0;
const offRouteFixesBeforeReroute = 3;

class NavState {
  const NavState({
    required this.route,
    required this.avoid,
    required this.destination,
    this.reason,
    this.pos,
    this.progress,
    this.rerouting = false,
    this.rerouteFailed = false,
  });
  final TripRoute route;
  final List<Segment> avoid;
  final Place destination;
  final String? reason;
  final LatLng? pos;
  final Progress? progress;
  final bool rerouting, rerouteFailed;

  bool get arrived => progress?.arrived ?? false;

  NavState copyWith({TripRoute? route, List<Segment>? avoid, String? Function()? reason, LatLng? pos, Progress? progress,
          bool? rerouting, bool? rerouteFailed}) =>
      NavState(
        route: route ?? this.route,
        avoid: avoid ?? this.avoid,
        destination: destination,
        reason: reason != null ? reason() : this.reason,
        pos: pos ?? this.pos,
        progress: progress ?? this.progress,
        rerouting: rerouting ?? this.rerouting,
        rerouteFailed: rerouteFailed ?? this.rerouteFailed,
      );
}

/// Follows the route chosen by the trip check. Three consecutive fixes more than 60 m off the route trigger a reroute
/// from the current position through the same risk pipeline, so a detour never leads back into a hazard zone.
class NavController extends Notifier<NavState> {
  late RouteTracker _tracker;
  var _offRoute = 0;

  @override
  NavState build() {
    final t = ref.read(tripControllerProvider);
    _tracker = RouteTracker(t.chosen!);
    ref.listen(userLocationProvider, (_, next) {
      final p = next.value;
      if (p != null) _onFix(p);
    }, fireImmediately: true);
    return NavState(route: t.chosen!, avoid: t.avoid, destination: t.to!, reason: t.reason);
  }

  void _onFix(LatLng p) {
    if (state.rerouting || state.arrived) return;
    final progress = _tracker.update(p);
    state = state.copyWith(pos: p, progress: progress, rerouteFailed: false);
    if (progress.offRouteM > offRouteMetres) {
      if (++_offRoute >= offRouteFixesBeforeReroute) _reroute(p);
    } else {
      _offRoute = 0;
    }
  }

  Future<void> _reroute(LatLng from) async {
    state = state.copyWith(rerouting: true);
    _offRoute = 0;
    try {
      final plan = await planTrip(ref.read(riskLayerProvider), from, state.destination.pos);
      _tracker = RouteTracker(plan.chosen);
      state = state.copyWith(
        route: plan.chosen,
        avoid: plan.avoid,
        reason: () => plan.diverted == null ? null : reasonFor(plan.avoid),
        progress: _tracker.update(from),
        rerouting: false,
      );
    } catch (_) {
      state = state.copyWith(rerouting: false, rerouteFailed: true);
    }
  }
}

final navControllerProvider = NotifierProvider.autoDispose<NavController, NavState>(NavController.new);
