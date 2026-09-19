import 'package:latlong2/latlong.dart';

import '../../mock_data/mock_fleet.dart';
import '../../mock_data/mock_incidents.dart' hide mockDistricts, mockFleet;
import '../../mock_data/models.dart';
import '../../shared/map/map_models.dart';
import '../../shared/map/ner_geo.dart';
import '../geo/geo_math.dart';
import 'geoserver_client.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Result models
// ═════════════════════════════════════════════════════════════════════════════

enum AnalyticsSource { geoserver, local }

class HighwayExposure {
  final String id;
  final double totalKm;
  final double floodKm;
  final double landslideKm;
  final int nearbyIncidents;
  const HighwayExposure({
    required this.id,
    required this.totalKm,
    required this.floodKm,
    required this.landslideKm,
    required this.nearbyIncidents,
  });

  double get exposedKm => floodKm + landslideKm;
  double get exposedShare => totalKm == 0 ? 0 : (exposedKm / totalKm).clamp(0, 1);
}

class ConvoyExposure {
  final String vehicleId;
  final String route;
  final String destination;
  final Priority risk;
  final MapZoneKind? zoneKind;
  final String? zoneName;
  final String nearestSafeZone;
  final double safeZoneKm;
  const ConvoyExposure({
    required this.vehicleId,
    required this.route,
    required this.destination,
    required this.risk,
    this.zoneKind,
    this.zoneName,
    required this.nearestSafeZone,
    required this.safeZoneKm,
  });

  bool get exposed => zoneKind != null;
}

class AreaIncidentSummary {
  final String area;
  final String state;
  final int critical, high, medium, low, open;
  const AreaIncidentSummary({
    required this.area,
    required this.state,
    this.critical = 0,
    this.high = 0,
    this.medium = 0,
    this.low = 0,
    this.open = 0,
  });

  int get total => critical + high + medium + low;
}

class RegionalAnalytics {
  final AnalyticsSource source;
  final List<HighwayExposure> highways;
  final List<ConvoyExposure> convoys;
  final List<AreaIncidentSummary> areas;

  /// Why local estimates are shown (GeoServer missing or failing).
  final String? note;
  const RegionalAnalytics({
    required this.source,
    required this.highways,
    required this.convoys,
    required this.areas,
    this.note,
  });
}

enum HazardKind { incident, flood, landslide }

class RouteHazard {
  final HazardKind kind;
  final String label;
  final Priority severity;

  /// Metres from the start of the queried route.
  final double alongM;
  final double offsetM;
  final LatLng point;
  const RouteHazard({
    required this.kind,
    required this.label,
    required this.severity,
    required this.alongM,
    required this.offsetM,
    required this.point,
  });
}

class RouteHazardReport {
  final AnalyticsSource source;
  final List<RouteHazard> hazards;
  final String? note;
  const RouteHazardReport(this.source, this.hazards, {this.note});
}

class LocationInsight {
  final AnalyticsSource source;
  final LatLng point;
  final List<({MapZoneKind kind, String name, String? susceptibility})> zones;
  final List<({String label, Priority severity, double km})> incidents;
  final ({String name, double km})? nearestSafeZone;
  final String? note;
  const LocationInsight({
    required this.source,
    required this.point,
    this.zones = const [],
    this.incidents = const [],
    this.nearestSafeZone,
    this.note,
  });
}

Priority priorityFrom(String s) => switch (s.toLowerCase()) {
      'critical' => Priority.critical,
      'high' => Priority.high,
      'medium' || 'moderate' => Priority.medium,
      _ => Priority.low,
    };

MapZoneKind? zoneKindFrom(String? s) => switch (s?.toLowerCase()) {
      'flood' => MapZoneKind.flood,
      'landslide' => MapZoneKind.landslide,
      'safe' => MapZoneKind.safe,
      _ => null,
    };

// ═════════════════════════════════════════════════════════════════════════════
// Sources
// ═════════════════════════════════════════════════════════════════════════════

abstract class SpatialAnalyticsSource {
  Future<RegionalAnalytics> regional();
  Future<RouteHazardReport> hazardsAlong(List<LatLng> route, {double bufferM});
  Future<LocationInsight> inspect(LatLng point, {double radiusKm});
}

/// Evenly spaced samples along [line] (for zone-entry tests).
List<({double m, LatLng p})> _samples(List<LatLng> line, double stepM) {
  final cum = GeoMath.cumulativeM(line);
  final total = cum.isEmpty ? 0.0 : cum.last;
  return [
    for (var m = 0.0; m <= total; m += stepM)
      (m: m, p: GeoMath.pointAtM(line, m, cum)),
  ];
}

/// Hazards along a route from incidents (within [bufferM]) and risk zones
/// (first point where the route enters them), sorted by distance.
List<RouteHazard> _routeHazards(
  List<LatLng> route,
  double bufferM,
  Iterable<({LatLng point, String label, Priority severity})> incidents,
  Iterable<({MapZoneKind kind, String name, bool Function(LatLng) contains})> zones,
) {
  final cum = GeoMath.cumulativeM(route);
  final out = <RouteHazard>[];
  for (final i in incidents) {
    final proj = GeoMath.project(route, i.point, cum);
    if (proj.offsetM <= bufferM) {
      out.add(RouteHazard(
        kind: HazardKind.incident,
        label: i.label,
        severity: i.severity,
        alongM: proj.alongM,
        offsetM: proj.offsetM,
        point: i.point,
      ));
    }
  }
  final samples = _samples(route, 200);
  for (final z in zones) {
    if (z.kind != MapZoneKind.flood && z.kind != MapZoneKind.landslide) continue;
    for (final s in samples) {
      if (z.contains(s.p)) {
        out.add(RouteHazard(
          kind: z.kind == MapZoneKind.flood ? HazardKind.flood : HazardKind.landslide,
          label: z.name,
          severity: z.kind == MapZoneKind.landslide ? Priority.high : Priority.medium,
          alongM: s.m,
          offsetM: 0,
          point: s.p,
        ));
        break;
      }
    }
  }
  out.sort((a, b) => a.alongM.compareTo(b.alongM));
  return out;
}

/// On-device estimates from the app's own data — same metrics as the
/// GeoServer views, so the UI can fall back without changing shape.
class LocalSpatialAnalytics implements SpatialAnalyticsSource {
  final String? note;
  const LocalSpatialAnalytics({this.note});

  static const _riskZones = [...NerGeo.floodZones, ...NerGeo.landslideZones];

  static bool _inZone(MapZone z, LatLng p) =>
      GeoMath.distanceM(z.center, p) <= z.radiusMeters;

  static ({String name, double km}) _nearestSafe(LatLng p) {
    final z = NerGeo.safeZones.reduce((a, b) =>
        GeoMath.distanceM(a.center, p) <= GeoMath.distanceM(b.center, p) ? a : b);
    return (name: z.label, km: GeoMath.distanceM(z.center, p) / 1000);
  }

  static Iterable<({LatLng point, String label, Priority severity, Incident source})>
      get _incidents => mockIncidents.map((i) => (
            point: NerGeo.locate(i.location, i.route),
            label: '${i.typeLabel} · ${i.location}',
            severity: i.severity,
            source: i,
          ));

  @override
  Future<RegionalAnalytics> regional() async {
    final incidents = _incidents.toList();
    final highways = <HighwayExposure>[];
    for (final e in NerGeo.highways.entries) {
      var flood = 0.0, slide = 0.0;
      const step = 250.0;
      for (final s in _samples(e.value, step)) {
        if (NerGeo.floodZones.any((z) => _inZone(z, s.p))) flood += step;
        if (NerGeo.landslideZones.any((z) => _inZone(z, s.p))) slide += step;
      }
      highways.add(HighwayExposure(
        id: e.key,
        totalKm: GeoMath.lengthM(e.value) / 1000,
        floodKm: flood / 1000,
        landslideKm: slide / 1000,
        nearbyIncidents: incidents
            .where((i) => GeoMath.distanceToLineM(i.point, e.value) <= 2000)
            .length,
      ));
    }
    highways.sort((a, b) => b.exposedKm.compareTo(a.exposedKm));

    final convoys = <ConvoyExposure>[];
    for (final v in NerGeo.vehicles(mockFleet)) {
      final fv = mockFleet.firstWhere((f) => f.id == v.id);
      MapZone? zone;
      for (final z in _riskZones) {
        if (_inZone(z, v.point)) {
          zone = z;
          break;
        }
      }
      final safe = _nearestSafe(v.point);
      convoys.add(ConvoyExposure(
        vehicleId: v.id,
        route: NerGeo.routeIdOf(fv.route),
        destination: fv.destination,
        risk: fv.risk,
        zoneKind: zone?.kind,
        zoneName: zone?.label,
        nearestSafeZone: safe.name,
        safeZoneKm: safe.km,
      ));
    }

    final byArea = <String, List<Incident>>{};
    final stateOf = <String, String>{};
    for (final i in incidents) {
      final t = NerGeo.nearestTown(i.point);
      byArea.putIfAbsent(t.name, () => []).add(i.source);
      stateOf[t.name] = t.state;
    }
    final areas = [
      for (final e in byArea.entries)
        AreaIncidentSummary(
          area: e.key,
          state: stateOf[e.key] ?? '',
          critical: e.value.where((i) => i.severity == Priority.critical).length,
          high: e.value.where((i) => i.severity == Priority.high).length,
          medium: e.value.where((i) => i.severity == Priority.medium).length,
          low: e.value.where((i) => i.severity == Priority.low).length,
          open: e.value.where((i) => i.statusLabel != 'Resolved').length,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));

    return RegionalAnalytics(
      source: AnalyticsSource.local,
      highways: highways,
      convoys: convoys,
      areas: areas,
      note: note,
    );
  }

  @override
  Future<RouteHazardReport> hazardsAlong(List<LatLng> route,
      {double bufferM = 2000}) async {
    final hazards = _routeHazards(
      route,
      bufferM,
      _incidents.where((i) => i.source.statusLabel != 'Resolved').map(
          (i) => (point: i.point, label: i.label, severity: i.severity)),
      _riskZones.map((z) =>
          (kind: z.kind, name: z.label, contains: (LatLng p) => _inZone(z, p))),
    );
    return RouteHazardReport(AnalyticsSource.local, hazards, note: note);
  }

  @override
  Future<LocationInsight> inspect(LatLng point, {double radiusKm = 25}) async {
    final nearby = [
      for (final i in _incidents)
        if (GeoMath.distanceM(point, i.point) <= radiusKm * 1000)
          (label: i.label, severity: i.severity, km: GeoMath.distanceM(point, i.point) / 1000),
    ]..sort((a, b) => a.km.compareTo(b.km));
    return LocationInsight(
      source: AnalyticsSource.local,
      point: point,
      zones: [
        for (final z in [..._riskZones, ...NerGeo.safeZones])
          if (_inZone(z, point)) (kind: z.kind, name: z.label, susceptibility: null),
      ],
      incidents: nearby,
      nearestSafeZone: _nearestSafe(point),
      note: note,
    );
  }
}

/// Analytics served by GeoServer from the PostGIS layers and views created
/// by `backend/geoserver` (workspace `ner`).
class GeoServerSpatialAnalytics implements SpatialAnalyticsSource {
  final GeoServerClient client;
  const GeoServerSpatialAnalytics(this.client);

  static const incidentsLayer = 'incidents';
  static const riskZonesLayer = 'risk_zones';
  static const safeZonesLayer = 'safe_zones';
  static const highwayExposureLayer = 'highway_risk_exposure';
  static const convoyExposureLayer = 'convoy_exposure';
  static const areaSummaryLayer = 'area_incident_summary';

  @override
  Future<RegionalAnalytics> regional() async {
    final results = await Future.wait([
      client.getFeatures(highwayExposureLayer, properties: const [
        'highway_id', 'total_km', 'flood_km', 'landslide_km', 'incidents_2km',
      ]),
      client.getFeatures(convoyExposureLayer),
      client.getFeatures(areaSummaryLayer),
    ]);
    return RegionalAnalytics(
      source: AnalyticsSource.geoserver,
      highways: [
        for (final f in results[0].features)
          HighwayExposure(
            id: f.str('highway_id'),
            totalKm: f.num_('total_km'),
            floodKm: f.num_('flood_km'),
            landslideKm: f.num_('landslide_km'),
            nearbyIncidents: f.int_('incidents_2km'),
          ),
      ]..sort((a, b) => b.exposedKm.compareTo(a.exposedKm)),
      convoys: [
        for (final f in results[1].features)
          ConvoyExposure(
            vehicleId: f.str('vehicle_id'),
            route: f.str('route'),
            destination: f.str('destination'),
            risk: priorityFrom(f.str('risk')),
            zoneKind: zoneKindFrom(f.properties['zone_kind'] as String?),
            zoneName: f.properties['zone_name'] as String?,
            nearestSafeZone: f.str('nearest_safe_zone', '—'),
            safeZoneKm: f.num_('safe_zone_km'),
          ),
      ],
      areas: [
        for (final f in results[2].features)
          AreaIncidentSummary(
            area: f.str('area'),
            state: f.str('state'),
            critical: f.int_('critical'),
            high: f.int_('high'),
            medium: f.int_('medium'),
            low: f.int_('low'),
            open: f.int_('open_count'),
          ),
      ]..sort((a, b) => b.total.compareTo(a.total)),
    );
  }

  @override
  Future<RouteHazardReport> hazardsAlong(List<LatLng> route,
      {double bufferM = 2000}) async {
    final box = GeoMath.bounds(route, padM: bufferM);
    final results = await Future.wait([
      client.getFeatures(incidentsLayer, bbox: box),
      client.getFeatures(riskZonesLayer, bbox: box),
    ]);
    final hazards = _routeHazards(
      route,
      bufferM,
      [
        for (final f in results[0].features)
          if (f.geometry?.anchor != null && f.str('status') != 'Resolved')
            (
              point: f.geometry!.anchor!,
              label: '${f.str('type_label')} · ${f.str('location')}',
              severity: priorityFrom(f.str('severity')),
            ),
      ],
      [
        for (final f in results[1].features)
          if (f.geometry != null && zoneKindFrom(f.str('kind')) != null)
            (
              kind: zoneKindFrom(f.str('kind'))!,
              name: f.str('name'),
              contains: f.geometry!.contains,
            ),
      ],
    );
    return RouteHazardReport(AnalyticsSource.geoserver, hazards);
  }

  @override
  Future<LocationInsight> inspect(LatLng point, {double radiusKm = 25}) async {
    final near = GeoMath.bounds([point], padM: radiusKm * 1000);
    final wide = GeoMath.bounds([point], padM: 150000);
    final results = await Future.wait([
      client.getFeatures(riskZonesLayer, bbox: GeoMath.bounds([point], padM: 50)),
      client.getFeatures(incidentsLayer, bbox: near),
      client.getFeatures(safeZonesLayer, bbox: wide),
    ]);
    ({String name, double km})? safe;
    for (final f in results[2].features) {
      final d = f.geometry?.distanceM(point);
      if (d != null && (safe == null || d / 1000 < safe.km)) {
        safe = (name: f.str('name'), km: d / 1000);
      }
    }
    return LocationInsight(
      source: AnalyticsSource.geoserver,
      point: point,
      zones: [
        for (final f in results[0].features)
          if (f.geometry?.contains(point) ?? false)
            (
              kind: zoneKindFrom(f.str('kind')) ?? MapZoneKind.impact,
              name: f.str('name'),
              susceptibility: f.properties['susceptibility'] as String?,
            ),
      ],
      incidents: [
        for (final f in results[1].features)
          if (f.geometry != null && f.geometry!.distanceM(point) <= radiusKm * 1000)
            (
              label: '${f.str('type_label')} · ${f.str('location')}',
              severity: priorityFrom(f.str('severity')),
              km: f.geometry!.distanceM(point) / 1000,
            ),
      ]..sort((a, b) => a.km.compareTo(b.km)),
      nearestSafeZone: safe,
    );
  }
}

/// Uses GeoServer when configured and reachable, otherwise local estimates
/// (labelled with the reason, so the UI never passes them off as live).
class SpatialAnalyticsService implements SpatialAnalyticsSource {
  final GeoServerSpatialAnalytics? remote;
  const SpatialAnalyticsService({this.remote});

  static const _notConfigured = 'GeoServer not configured — on-device estimate';

  Future<T> _withFallback<T>(
    Future<T> Function(SpatialAnalyticsSource s) run,
  ) async {
    if (remote == null) {
      return run(const LocalSpatialAnalytics(note: _notConfigured));
    }
    try {
      return await run(remote!);
    } on GeoServerException catch (e) {
      return run(LocalSpatialAnalytics(
          note: 'GeoServer unavailable (${e.message}) — on-device estimate'));
    }
  }

  @override
  Future<RegionalAnalytics> regional() => _withFallback((s) => s.regional());

  @override
  Future<RouteHazardReport> hazardsAlong(List<LatLng> route,
          {double bufferM = 2000}) =>
      _withFallback((s) => s.hazardsAlong(route, bufferM: bufferM));

  @override
  Future<LocationInsight> inspect(LatLng point, {double radiusKm = 25}) =>
      _withFallback((s) => s.inspect(point, radiusKm: radiusKm));
}
