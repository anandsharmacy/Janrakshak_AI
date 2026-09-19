import 'package:latlong2/latlong.dart';

/// Rider-facing logistics domain: the signed-in rider, the riders around
/// them, the assigned road corridor and the incident on it.
///
/// Pure Dart (no Flutter) so the service and tests can use it directly.

enum RiderStatus { active, inactive }

extension RiderStatusLabel on RiderStatus {
  String get label => this == RiderStatus.active ? 'Active' : 'Inactive';

  static RiderStatus parse(String value) =>
      value.trim().toLowerCase() == 'active' ? RiderStatus.active : RiderStatus.inactive;
}

/// Status of the route the rider is driving. Uppercase labels match the
/// control-room vocabulary shown on the officer dashboards.
enum RiderRouteStatus { open, atRisk, blocked, diverted }

extension RiderRouteStatusLabel on RiderRouteStatus {
  String get label => switch (this) {
        RiderRouteStatus.open => 'OPEN',
        RiderRouteStatus.atRisk => 'AT RISK',
        RiderRouteStatus.blocked => 'BLOCKED',
        RiderRouteStatus.diverted => 'DIVERTED',
      };
}

/// Observable steps of the rider journey, in demo order. Every value is a
/// UI state the panel renders, so the flow can be walked step by step.
enum RiderFlowStage {
  home,
  currentLocation,
  nearbyRiders,
  incidentDetected,
  safetyWarning,
  alternateReady,
  diversionConfirmed,
  routeSwitched,
  continuing,
  arrived,
}

extension RiderFlowStageLabel on RiderFlowStage {
  String get label => switch (this) {
        RiderFlowStage.home => 'Rider home',
        RiderFlowStage.currentLocation => 'On assigned route',
        RiderFlowStage.nearbyRiders => 'Nearby riders in range',
        RiderFlowStage.incidentDetected => 'Incident detected ahead',
        RiderFlowStage.safetyWarning => 'Route safety warning',
        RiderFlowStage.alternateReady => 'Alternate route ready',
        RiderFlowStage.diversionConfirmed => 'Diversion confirmed',
        RiderFlowStage.routeSwitched => 'Following new route',
        RiderFlowStage.continuing => 'Continuing to destination',
        RiderFlowStage.arrived => 'Arrived at destination',
      };
}

/// A rider as the mobile app sees one: identity, vehicle, live position and
/// the route being driven. Built by the data layer; the UI never constructs
/// one itself.
class Rider {
  final String id;
  final String name;
  final String callsign;

  /// Only ever rendered on the signed-in rider's own profile.
  final String? phone;
  final String state;
  final String district;
  final String vehicleType;
  final double rating;
  final RiderStatus status;

  final double latitude;
  final double longitude;
  /// Degrees clockwise from north; null when stationary.
  final double? heading;
  /// km/h.
  final double speed;

  final String? routeId;
  final String? origin;
  final String? destination;
  /// Time left to the destination; null when no route is assigned.
  final Duration? eta;

  /// Road being driven now (original or diverted), origin → destination.
  final List<LatLng> currentRoute;
  final RiderRouteStatus routeStatus;
  /// 0–1 along [currentRoute].
  final double routeProgress;

  final bool isOffline;
  final DateTime? lastLocationUpdate;

  const Rider({
    required this.id,
    required this.name,
    required this.callsign,
    required this.state,
    required this.district,
    required this.vehicleType,
    required this.rating,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.phone,
    this.heading,
    this.speed = 0,
    this.routeId,
    this.origin,
    this.destination,
    this.eta,
    this.currentRoute = const [],
    this.routeStatus = RiderRouteStatus.open,
    this.routeProgress = 0,
    this.isOffline = false,
    this.lastLocationUpdate,
  });

  LatLng get point => LatLng(latitude, longitude);
  bool get isActive => status == RiderStatus.active;
  String get speedLabel => '${speed.round()} km/h';

  /// `R001` → `FALCON-1`. Deterministic so a callsign never needs storing.
  static String callsignFor(String riderId) {
    final digits = RegExp(r'\d+').firstMatch(riderId)?.group(0);
    final n = digits == null ? null : int.tryParse(digits);
    return n == null ? riderId.toUpperCase() : 'FALCON-$n';
  }

  Rider copyWith({
    double? latitude,
    double? longitude,
    Object? heading = _sentinel,
    double? speed,
    String? routeId,
    String? origin,
    String? destination,
    Object? eta = _sentinel,
    List<LatLng>? currentRoute,
    RiderRouteStatus? routeStatus,
    double? routeProgress,
    bool? isOffline,
    DateTime? lastLocationUpdate,
  }) =>
      Rider(
        id: id,
        name: name,
        callsign: callsign,
        phone: phone,
        state: state,
        district: district,
        vehicleType: vehicleType,
        rating: rating,
        status: status,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        heading: identical(heading, _sentinel) ? this.heading : heading as double?,
        speed: speed ?? this.speed,
        routeId: routeId ?? this.routeId,
        origin: origin ?? this.origin,
        destination: destination ?? this.destination,
        eta: identical(eta, _sentinel) ? this.eta : eta as Duration?,
        currentRoute: currentRoute ?? this.currentRoute,
        routeStatus: routeStatus ?? this.routeStatus,
        routeProgress: routeProgress ?? this.routeProgress,
        isOffline: isOffline ?? this.isOffline,
        lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      );

  static const _sentinel = Object();
}

/// A road corridor assigned to a rider. [waypoints] follow the real road
/// shape (never a straight line for the primary rider). [alternate], when
/// present, starts at a point on the corridor before the incident and ends
/// at the destination.
class RiderRoute {
  final String id;
  final String riderId;
  final String origin;
  final String destination;
  final List<LatLng> waypoints;
  final List<LatLng> alternate;

  const RiderRoute({
    required this.id,
    required this.riderId,
    required this.origin,
    required this.destination,
    required this.waypoints,
    this.alternate = const [],
  });

  LatLng get start => waypoints.first;
  LatLng get end => waypoints.last;
  bool get hasAlternate => alternate.length >= 2;
}

/// The demo incident placed on a route at a fixed waypoint, so the
/// safety-warning flow is reproducible.
class RouteIncident {
  final String id;
  final String routeId;
  final int waypointIndex;
  final LatLng point;
  final String title;
  final String location;
  final String description;

  const RouteIncident({
    required this.id,
    required this.routeId,
    required this.waypointIndex,
    required this.point,
    required this.title,
    required this.location,
    required this.description,
  });
}
