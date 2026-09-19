import 'package:latlong2/latlong.dart';

import 'region_data.dart';
import 'taxonomy.dart';

// roundResult defaults to true (whole km / whole degrees), which zeroes every short segment of a route.
const _km = Distance(roundResult: false);
double distanceKm(LatLng a, LatLng b) => _km.as(LengthUnit.Kilometer, a, b);

/// One item of the citizen feed (alert, verified disaster or triaged incident). Coordinates are optional:
/// some alerts only carry a district/state, so they list but cannot be plotted or route-checked.
class Hazard {
  const Hazard({
    required this.id,
    required this.type,
    required this.severity,
    required this.state,
    required this.district,
    required this.summary,
    required this.source,
    required this.at,
    this.center,
    this.radiusKm = 10,
  });
  final String id, type, state, district, summary;
  final Severity severity;
  final ReportSource source;
  final DateTime at;
  final LatLng? center;
  final double radiusKm;

  String get region => RegionData.regionOf(state) ?? '';
  bool covers(LatLng p) => center != null && distanceKm(center!, p) <= radiusKm;
}
