import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../services/geo/geo_math.dart';
import '../../../auth/application/auth_controller.dart';
import '../data/mock_rider_data_source.dart';
import '../domain/rider.dart';
import '../domain/rider_data_repository.dart';

// ── Tunables ────────────────────────────────────────────────────────────────

/// Other riders are shown only inside this radius of the signed-in rider.
const kNearbyRadiusM = 50_000.0;

/// The safety warning fires when the incident is this close along the road.
const kIncidentTriggerDistanceM = 10_000.0;

/// A rider who has not diverted stops this far before the incident.
const kHaltBeforeIncidentM = 300.0;

/// Client-side interpolation cadence.
const kTickInterval = Duration(seconds: 2);

/// Simulated seconds per real second, so the ~100 km demo corridor plays in
/// minutes rather than hours. 1 = real time.
const kDemoTimeScale = 30.0;

/// Cruising speed of the primary rider (varies ±[kSpeedSwingKmph] per tick).
const kBaseSpeedKmph = 42.0;
const kSpeedSwingKmph = 4.0;

/// Cruising speed of nearby riders on their district tracks.
const kNearbySpeedKmph = 30.0;

/// Where on the corridor the demo starts (0 = origin). Set so the incident
/// warning appears within a minute of opening the trip.
const kDemoStartFraction = 0.35;

// ── State ───────────────────────────────────────────────────────────────────

class RiderLogisticsState {
  /// The signed-in rider with live position; null while loading or when the
  /// account maps to no rider.
  final Rider? rider;

  /// Active riders inside [kNearbyRadiusM], excluding [rider].
  final List<Rider> nearby;

  final RiderRoute? route;
  final RouteIncident? incident;

  final RiderFlowStage stage;

  /// Road being driven, origin → destination (original, or with the detour
  /// spliced in after confirmation).
  final List<LatLng> activePath;

  /// Metres driven along [activePath].
  final double alongM;

  /// Metres from the origin to the incident along the original road
  /// (infinity when the route has no incident).
  final double incidentAlongM;

  /// True once the incident is inside the trigger distance.
  final bool incidentDetected;

  /// True after the rider confirmed the diversion.
  final bool diverted;

  /// True when the rider is held before the blocked stretch.
  final bool halted;

  /// The stretch of the original road no longer driven, kept for the map.
  final List<LatLng> avoidedPath;

  /// The rider hid the banner; the compact reminder stays until diverted.
  final bool warningDismissed;

  final String? selectedNearbyId;
  final bool loading;
  final String? error;

  const RiderLogisticsState({
    this.rider,
    this.nearby = const [],
    this.route,
    this.incident,
    this.stage = RiderFlowStage.home,
    this.activePath = const [],
    this.alongM = 0,
    this.incidentAlongM = double.infinity,
    this.incidentDetected = false,
    this.diverted = false,
    this.halted = false,
    this.avoidedPath = const [],
    this.warningDismissed = false,
    this.selectedNearbyId,
    this.loading = true,
    this.error,
  });

  double get pathLengthM => GeoMath.lengthM(activePath);
  double get remainingM => math.max(0, pathLengthM - alongM);

  /// Road metres between the rider and the incident (0 when at or past it).
  double get incidentAheadM =>
      incidentAlongM.isFinite ? math.max(0, incidentAlongM - alongM) : 0;
  List<LatLng> get travelled => activePath.length < 2 ? activePath : GeoMath.sliceM(activePath, 0, alongM);
  List<LatLng> get ahead => activePath.length < 2 ? activePath : GeoMath.sliceM(activePath, alongM, pathLengthM);

  /// The offered detour from its branch point to the destination, shown as a
  /// candidate line until the rider confirms.
  List<LatLng> get offeredAlternate =>
      incidentDetected && !diverted && (route?.hasAlternate ?? false) ? route!.alternate : const [];

  /// Warning is live from detection until the rider diverts.
  bool get warningActive => incidentDetected && !diverted;
  bool get canConfirmDiversion => warningActive && stage.index >= RiderFlowStage.alternateReady.index;

  Rider? get selectedNearby {
    for (final r in nearby) {
      if (r.id == selectedNearbyId) return r;
    }
    return null;
  }

  RiderLogisticsState copyWith({
    Object? rider = _sentinel,
    List<Rider>? nearby,
    Object? route = _sentinel,
    Object? incident = _sentinel,
    RiderFlowStage? stage,
    List<LatLng>? activePath,
    double? alongM,
    double? incidentAlongM,
    bool? incidentDetected,
    bool? diverted,
    bool? halted,
    List<LatLng>? avoidedPath,
    bool? warningDismissed,
    Object? selectedNearbyId = _sentinel,
    bool? loading,
    Object? error = _sentinel,
  }) =>
      RiderLogisticsState(
        rider: identical(rider, _sentinel) ? this.rider : rider as Rider?,
        nearby: nearby ?? this.nearby,
        route: identical(route, _sentinel) ? this.route : route as RiderRoute?,
        incident: identical(incident, _sentinel) ? this.incident : incident as RouteIncident?,
        stage: stage ?? this.stage,
        activePath: activePath ?? this.activePath,
        alongM: alongM ?? this.alongM,
        incidentAlongM: incidentAlongM ?? this.incidentAlongM,
        incidentDetected: incidentDetected ?? this.incidentDetected,
        diverted: diverted ?? this.diverted,
        halted: halted ?? this.halted,
        avoidedPath: avoidedPath ?? this.avoidedPath,
        warningDismissed: warningDismissed ?? this.warningDismissed,
        selectedNearbyId:
            identical(selectedNearbyId, _sentinel) ? this.selectedNearbyId : selectedNearbyId as String?,
        loading: loading ?? this.loading,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

// ── Service ─────────────────────────────────────────────────────────────────

/// The only layer the rider UI talks to. Resolves the signed-in rider from
/// the auth session, loads route/incident/nearby data through
/// [RiderDataRepository], and advances the demo simulation on a fixed tick.
class RiderLogisticsService extends Notifier<RiderLogisticsState> {
  Timer? _timer;
  int _ticks = 0;
  double _incidentAlongM = double.infinity;
  final _others = <String, _TrackProgress>{};
  List<Rider> _allRiders = const [];
  Map<String, RiderRoute> _otherRoutes = const {};
  String? _loadedUserId;

  RiderDataRepository get _repo => ref.read(riderDataRepositoryProvider);

  @override
  RiderLogisticsState build() {
    ref.onDispose(_stop);
    final profile = ref.watch(currentProfileProvider);
    if (profile == null) {
      _stop();
      return const RiderLogisticsState(loading: false);
    }
    if (profile.userId != _loadedUserId) {
      _loadedUserId = profile.userId;
      unawaited(_load(profile.userId, officerId: profile.officerId, email: profile.email));
    }
    return const RiderLogisticsState();
  }

  Future<void> _load(String userId, {String? officerId, String? email}) async {
    try {
      final me = await _repo.riderForUser(userId: userId, officerId: officerId, email: email);
      if (me == null) {
        state = state.copyWith(loading: false, error: 'No rider record for this account.');
        return;
      }
      _allRiders = await _repo.fetchRiders();
      final route = await _repo.assignedRoute(me.id);
      final incident = route == null ? null : await _repo.incidentOnRoute(route.id);

      _otherRoutes = {};
      _others.clear();
      for (final r in _allRiders) {
        if (r.id == me.id || !r.isActive) continue;
        final rr = await _repo.assignedRoute(r.id);
        if (rr != null && rr.waypoints.length >= 2) {
          _otherRoutes[r.id] = rr;
          _others[r.id] = _TrackProgress(0, 1);
        }
      }

      final path = route?.waypoints ?? [me.point];
      final startM = GeoMath.lengthM(path) * kDemoStartFraction;
      _incidentAlongM = incident == null || path.length < 2
          ? double.infinity
          : GeoMath.project(path, incident.point).alongM;

      state = RiderLogisticsState(
        rider: _place(me, path, startM, speed: kBaseSpeedKmph, status: RiderRouteStatus.open),
        route: route,
        incident: incident,
        activePath: path,
        alongM: startM,
        incidentAlongM: _incidentAlongM,
        stage: RiderFlowStage.currentLocation,
        loading: false,
        nearby: _nearbyOf(GeoMath.pointAtM(path, startM), me.id),
      );
      if (ref.read(riderLogisticsAutoTickProvider)) {
        _timer ??= Timer.periodic(kTickInterval, (_) => tick());
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Rider data unavailable: $e');
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Rider actions ─────────────────────────────────────────────────────────

  /// Explicit rider confirmation: splices the alternate into the driven road
  /// from the current position. Never called automatically.
  void confirmDiversion() {
    final s = state;
    final route = s.route;
    final rider = s.rider;
    if (rider == null || route == null || !s.canConfirmDiversion) return;

    final here = GeoMath.pointAtM(s.activePath, s.alongM);
    // The alternate leaves the road at its first point. Reach that point on
    // the road itself: forward if it is still ahead, back along the road if
    // the rider is already past it (e.g. stopped at the blockage).
    final branchAlongM = GeoMath.project(s.activePath, route.alternate.first).alongM;
    final toBranch = s.alongM <= branchAlongM
        ? GeoMath.sliceM(s.activePath, s.alongM, branchAlongM)
        : GeoMath.sliceM(s.activePath, branchAlongM, s.alongM).reversed.toList();
    final newPath = [...s.travelled, ...toBranch.skip(1), ...route.alternate.skip(1)];
    final avoided = s.ahead;
    // The travelled slice keeps its length, so alongM stays valid on newPath.
    final alongM = GeoMath.lengthM(s.travelled);

    state = s.copyWith(
      activePath: newPath,
      alongM: alongM,
      avoidedPath: avoided,
      diverted: true,
      halted: false,
      warningDismissed: false,
      stage: RiderFlowStage.diversionConfirmed,
      rider: _place(rider, newPath, alongM,
          speed: rider.speed == 0 ? kBaseSpeedKmph : rider.speed,
          status: RiderRouteStatus.diverted,
          at: here),
    );
  }

  /// Hides the banner. The route stays AT RISK and a compact reminder remains
  /// until the rider diverts, so the warning is never silently lost.
  void dismissWarning() {
    if (!state.warningActive) return;
    state = state.copyWith(warningDismissed: true);
  }

  void reviewWarning() => state = state.copyWith(warningDismissed: false);

  void selectNearby(String? riderId) =>
      state = state.copyWith(selectedNearbyId: state.selectedNearbyId == riderId ? null : riderId);

  // ── Simulation ────────────────────────────────────────────────────────────

  /// One interpolation step. Public so tests can drive the flow without timers.
  @visibleForTesting
  void tick() {
    final s = state;
    final rider = s.rider;
    if (rider == null || s.loading || s.stage == RiderFlowStage.arrived) return;
    _ticks++;

    final dt = kTickInterval.inMilliseconds / 1000 * kDemoTimeScale;
    var speed = kBaseSpeedKmph + kSpeedSwingKmph * math.sin(_ticks / 9);
    var alongM = s.alongM + speed / 3.6 * dt;
    var halted = false;
    var detected = s.incidentDetected;
    var status = rider.routeStatus;
    var stage = s.stage;

    if (!s.diverted && s.incident != null) {
      if (!detected && _incidentAlongM - alongM <= kIncidentTriggerDistanceM) {
        detected = true;
        status = RiderRouteStatus.atRisk;
        stage = RiderFlowStage.incidentDetected;
      }
      if (detected) {
        final holdAt = _incidentAlongM - kHaltBeforeIncidentM;
        if (alongM >= holdAt) {
          alongM = math.max(s.alongM, holdAt);
          halted = true;
          speed = 0;
          status = RiderRouteStatus.blocked;
        }
      }
    }

    final length = s.pathLengthM;
    if (alongM >= length) {
      alongM = length;
      speed = 0;
      stage = RiderFlowStage.arrived;
    }

    // Transient flow stages advance one tick at a time so each is visible.
    stage = switch (stage) {
      RiderFlowStage.incidentDetected when s.stage == RiderFlowStage.incidentDetected =>
        RiderFlowStage.safetyWarning,
      RiderFlowStage.safetyWarning => RiderFlowStage.alternateReady,
      RiderFlowStage.diversionConfirmed => RiderFlowStage.routeSwitched,
      RiderFlowStage.routeSwitched => RiderFlowStage.continuing,
      _ => stage,
    };

    _advanceOthers(dt);
    final here = GeoMath.pointAtM(s.activePath, alongM);
    final nearby = _nearbyOf(here, rider.id);
    if (stage == RiderFlowStage.currentLocation && nearby.isNotEmpty) {
      stage = RiderFlowStage.nearbyRiders;
    }

    state = s.copyWith(
      alongM: alongM,
      incidentDetected: detected,
      halted: halted,
      stage: stage,
      nearby: nearby,
      rider: _place(rider, s.activePath, alongM, speed: speed, status: status, at: here),
    );
  }

  void _advanceOthers(double dt) {
    for (final e in _otherRoutes.entries) {
      final p = _others[e.key]!;
      final len = GeoMath.lengthM(e.value.waypoints);
      var m = p.alongM + kNearbySpeedKmph / 3.6 * dt * p.direction;
      var dir = p.direction;
      if (m >= len) {
        m = len;
        dir = -1;
      } else if (m <= 0) {
        m = 0;
        dir = 1;
      }
      _others[e.key] = _TrackProgress(m, dir);
    }
  }

  /// Active riders other than [meId] within [kNearbyRadiusM] of [here].
  List<Rider> _nearbyOf(LatLng here, String meId) {
    final out = <Rider>[];
    for (final r in _allRiders) {
      if (r.id == meId || !r.isActive) continue;
      final route = _otherRoutes[r.id];
      final progress = _others[r.id];
      final placed = route == null || progress == null
          ? r
          : _place(r, route.waypoints, progress.alongM,
              speed: kNearbySpeedKmph, status: RiderRouteStatus.open, direction: progress.direction);
      if (GeoMath.distanceM(here, placed.point) <= kNearbyRadiusM) out.add(placed);
    }
    return out;
  }

  /// Positions [rider] [alongM] metres along [path] and derives heading, ETA
  /// and progress from that position and [speed].
  Rider _place(
    Rider rider,
    List<LatLng> path,
    double alongM, {
    required double speed,
    required RiderRouteStatus status,
    LatLng? at,
    int direction = 1,
  }) {
    final length = GeoMath.lengthM(path);
    final here = at ?? GeoMath.pointAtM(path, alongM);
    final probe = GeoMath.pointAtM(path, (alongM + 200 * direction).clamp(0, length));
    final remaining = direction > 0 ? math.max(0.0, length - alongM) : alongM;
    return rider.copyWith(
      latitude: here.latitude,
      longitude: here.longitude,
      heading: speed <= 0 || probe == here ? null : GeoMath.bearingDeg(here, probe),
      speed: speed,
      eta: speed <= 0 || length == 0 ? null : Duration(seconds: (remaining / (speed / 3.6)).round()),
      currentRoute: path,
      routeStatus: status,
      routeProgress: length == 0 ? 0 : (alongM / length).clamp(0, 1),
      lastLocationUpdate: DateTime.now(),
    );
  }
}

class _TrackProgress {
  final double alongM;
  final int direction;
  const _TrackProgress(this.alongM, this.direction);
}

// ── Providers ───────────────────────────────────────────────────────────────

/// Swap the implementation here to move off demo data; nothing else changes.
final riderDataRepositoryProvider =
    Provider<RiderDataRepository>((ref) => const MockRiderDataSource());

/// Override with `false` in tests to drive [RiderLogisticsService.tick] manually.
final riderLogisticsAutoTickProvider = Provider<bool>((_) => true);

final riderLogisticsProvider =
    NotifierProvider<RiderLogisticsService, RiderLogisticsState>(RiderLogisticsService.new);
