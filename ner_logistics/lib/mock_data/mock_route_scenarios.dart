import 'package:latlong2/latlong.dart';

/// Demo trips routed live through OSRM.
///
/// Only the endpoints, the hazard location and the vehicle's position are
/// scenario data — geometry, distances, ETAs, km markers and turn
/// instructions all come from the routing engine.
class RouteScenario {
  final String id;
  final String originLabel;
  final String destinationLabel;
  final List<LatLng> waypoints;

  /// Predicted hazard on the route (snapped onto the route at runtime).
  final LatLng? hazardPoint;
  final double hazardHalfSpanM;
  final String hazardLabel;
  final int hazardConfidence;

  /// Earlier, lower-severity caution segment.
  final LatLng? cautionPoint;
  final double cautionHalfSpanM;
  final String cautionLabel;

  /// Vehicle position: metres before the hazard, or a fraction of the route
  /// when there is no hazard.
  final double vehicleBeforeHazardM;
  final double vehicleFraction;

  /// How far along the detour the vehicle is once it follows the reroute.
  final double postRerouteAdvanceM;

  const RouteScenario({
    required this.id,
    required this.originLabel,
    required this.destinationLabel,
    required this.waypoints,
    this.hazardPoint,
    this.hazardHalfSpanM = 1500,
    this.hazardLabel = '',
    this.hazardConfidence = 0,
    this.cautionPoint,
    this.cautionHalfSpanM = 2000,
    this.cautionLabel = '',
    this.vehicleBeforeHazardM = 12000,
    this.vehicleFraction = 0,
    this.postRerouteAdvanceM = 3000,
  });

  LatLng get destination => waypoints.last;
}

/// TRP-2291 · Guwahati depot → Sonapur via Shillong and Jowai (NH-6).
/// The hazard sits on the NH-6 cut slopes west of Jowai, where OSRM finds a
/// real road detour (checked against the public server, Sep 2026).
const fieldTripScenario = RouteScenario(
  id: 'TRP-2291',
  originLabel: 'Guwahati Depot',
  destinationLabel: 'Sonapur',
  waypoints: [LatLng(26.1445, 91.7362), LatLng(25.0455, 92.4205)],
  hazardPoint: LatLng(25.4829, 92.1977),
  hazardLabel: 'Predicted landslide',
  hazardConfidence: 78,
  cautionPoint: LatLng(25.5155, 92.1574),
  cautionLabel: 'Wet slope, reduce speed',
);

/// ASN-4821 · Guwahati Medical Depot → Nongpoh Civil Hospital (NH-6).
const riderTripScenario = RouteScenario(
  id: 'TRP-R-4821',
  originLabel: 'Guwahati Medical Depot',
  destinationLabel: 'Nongpoh Civil Hospital',
  waypoints: [LatLng(26.1545, 91.7700), LatLng(25.9095, 91.8768)],
  vehicleFraction: 0.58,
);
