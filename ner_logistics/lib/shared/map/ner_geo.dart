import 'package:latlong2/latlong.dart';

import '../../mock_data/models.dart';
import '../../services/geo/geo_math.dart';
import 'generated/geo_snapshot.g.dart';
import 'map_models.dart';

/// NerGeo — geographic reference data for the North Eastern Region.
///
/// Pure Dart (no Flutter) so `tool/generate_geodata.dart` can use it.
/// Town coordinates are checked against OSRM `/nearest` (all within ~1 km of
/// a road). Highway lines come from OSRM road geometry baked into
/// `generated/geo_snapshot.g.dart`; the hand-placed [highwayWaypoints] are
/// the fallback and the input to the generator.
class NerGeo {
  NerGeo._();

  // ── Region extent (pan limit for every map) ───────────────────────────────
  static const regionSouthWest = LatLng(21.5, 87.5);
  static const regionNorthEast = LatLng(29.8, 97.6);

  // ── Places ────────────────────────────────────────────────────────────────
  static const guwahati = LatLng(26.1445, 91.7362);
  static const jorabat = LatLng(26.1030, 91.8740);
  static const nongpoh = LatLng(25.9030, 91.8770);
  static const umiam = LatLng(25.6600, 91.8930);
  static const shillong = LatLng(25.5788, 91.8933);
  static const jowai = LatLng(25.4505, 92.2089);
  static const khliehriat = LatLng(25.3587, 92.3670);
  static const lumshnong = LatLng(25.1840, 92.3767);
  static const umkiang = LatLng(25.0623, 92.3846);
  static const sonapur = LatLng(25.0455, 92.4205);
  static const badarpur = LatLng(24.8680, 92.5960);
  static const silchar = LatLng(24.8333, 92.7789);
  static const kolasib = LatLng(24.2240, 92.6760);
  static const aizawl = LatLng(23.7271, 92.7176);
  static const srirampur = LatLng(26.4430, 89.9830);
  static const bongaigaon = LatLng(26.4770, 90.5580);
  static const barpetaRoad = LatLng(26.5030, 90.9700);
  static const barpeta = LatLng(26.3230, 91.0060);
  static const nalbari = LatLng(26.4450, 91.4400);
  static const rangia = LatLng(26.4500, 91.6100);
  static const nagaon = LatLng(26.3480, 92.6840);
  static const tezpur = LatLng(26.6338, 92.7926);
  static const bokakhat = LatLng(26.6400, 93.6000);
  static const jorhat = LatLng(26.7509, 94.2037);
  static const numaligarh = LatLng(26.6200, 93.7200);
  static const golaghat = LatLng(26.5200, 93.9700);
  static const bokajan = LatLng(26.0200, 93.7700);
  static const dimapur = LatLng(25.9060, 93.7270);
  static const chumukedima = LatLng(25.7900, 93.7800);
  static const piphema = LatLng(25.7200, 93.9300);
  static const kohima = LatLng(25.6747, 94.1086);
  static const mao = LatLng(25.5143, 94.1362);
  static const senapati = LatLng(25.2670, 94.0200);
  static const imphal = LatLng(24.8170, 93.9368);
  static const itanagar = LatLng(27.0844, 93.6053);
  static const bhalukpong = LatLng(27.0130, 92.6430);
  static const bomdila = LatLng(27.2645, 92.4159);
  static const dirang = LatLng(27.3580, 92.2400);
  static const selaPass = LatLng(27.5050, 92.1050);
  static const tawang = LatLng(27.5860, 91.8660);
  static const siliguri = LatLng(26.7271, 88.3953);
  static const sevoke = LatLng(26.8890, 88.4720);
  static const rangpo = LatLng(27.1760, 88.5300);
  static const gangtok = LatLng(27.3389, 88.6065);

  /// Lookup for free-text destinations such as `'Kohima'` or `'Tezpur'`.
  static const Map<String, LatLng> _towns = {
    'guwahati': guwahati, 'jorabat': jorabat, 'nongpoh': nongpoh,
    'shillong': shillong, 'jowai': jowai, 'sonapur': sonapur,
    'silchar': silchar, 'aizawl': aizawl, 'barpeta': barpeta,
    'bongaigaon': bongaigaon, 'nagaon': nagaon, 'tezpur': tezpur,
    'jorhat': jorhat, 'golaghat': golaghat, 'dimapur': dimapur,
    'chumukedima': chumukedima, 'kohima': kohima, 'imphal': imphal,
    'itanagar': itanagar, 'bomdila': bomdila, 'tawang': tawang,
    'siliguri': siliguri, 'gangtok': gangtok,
  };

  static LatLng? town(String name) {
    final key = name.toLowerCase();
    for (final e in _towns.entries) {
      if (key.contains(e.key)) return e.value;
    }
    return null;
  }

  static const Map<String, String> _townState = {
    'guwahati': 'Assam', 'jorabat': 'Assam', 'barpeta': 'Assam',
    'bongaigaon': 'Assam', 'nagaon': 'Assam', 'tezpur': 'Assam',
    'jorhat': 'Assam', 'golaghat': 'Assam', 'silchar': 'Assam',
    'nongpoh': 'Meghalaya', 'shillong': 'Meghalaya', 'jowai': 'Meghalaya',
    'sonapur': 'Meghalaya', 'dimapur': 'Nagaland', 'chumukedima': 'Nagaland',
    'kohima': 'Nagaland', 'imphal': 'Manipur', 'aizawl': 'Mizoram',
    'itanagar': 'Arunachal Pradesh', 'bomdila': 'Arunachal Pradesh',
    'tawang': 'Arunachal Pradesh', 'gangtok': 'Sikkim', 'siliguri': 'West Bengal',
  };

  /// Closest known town to [p] — used to group incidents by area.
  static ({String name, String state}) nearestTown(LatLng p) {
    var best = _towns.entries.first;
    var bestD = double.infinity;
    for (final e in _towns.entries) {
      final d = GeoMath.distanceM(p, e.value);
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    final name = best.key[0].toUpperCase() + best.key.substring(1);
    return (name: name, state: _townState[best.key] ?? '');
  }

  // ── Highways (keyed by NH number) ─────────────────────────────────────────
  /// Ordered waypoints per highway — OSRM routes through these to produce
  /// the real road line.
  static const Map<String, List<LatLng>> highwayWaypoints = {
    'NH-27': [srirampur, bongaigaon, barpetaRoad, nalbari, rangia, guwahati],
    'NH-2': [kohima, mao, senapati, imphal],
    'NH-29': [dimapur, chumukedima, piphema, kohima],
    'NH-39': [numaligarh, golaghat, bokajan, dimapur],
    'NH-37': [nagaon, bokakhat, jorhat],
    'NH-306': [silchar, kolasib, aizawl],
    'NH-6': [shillong, jowai, khliehriat, lumshnong, umkiang, sonapur, badarpur, silchar],
    'NH-40': [jorabat, nongpoh, umiam, shillong],
    'NH-13': [bhalukpong, bomdila, dirang, selaPass, tawang],
    'NH-10': [siliguri, sevoke, rangpo, gangtok],
  };

  /// Road-snapped geometry when the snapshot has it, else the waypoints.
  static final Map<String, List<LatLng>> highways = {
    for (final e in highwayWaypoints.entries)
      e.key: kHighwayPolylines.containsKey(e.key)
          ? GeoMath.decodePolyline(kHighwayPolylines[e.key]!)
          : e.value,
  };

  /// Extracts the NH number from strings like `'NH-27 › Guwahati → Siliguri'`.
  static String routeIdOf(String route) => route.split(' ').first.trim();

  static List<LatLng>? highway(String route) => highways[routeIdOf(route)];

  /// Incident / report locations that don't map to a town name directly.
  static const Map<String, LatLng> _places = {
    'barpeta': barpeta,
    'tawang': LatLng(27.5500, 91.9500),
    'dimapur': dimapur,
    'silchar': silchar,
    'shillong': shillong,
    'jorabat': jorabat,
    'siliguri': siliguri,
    'guwahati': LatLng(26.1400, 91.7900),
    'jorhat': jorhat,
    'kohima': kohima,
  };

  /// Best-effort coordinate for an incident: known place name → `Km` marker
  /// along its highway → midpoint of its highway → Guwahati.
  static LatLng locate(String location, String route) {
    final loc = location.toLowerCase();
    for (final e in _places.entries) {
      if (loc.contains(e.key)) return e.value;
    }
    final line = highway(route);
    if (line == null) return guwahati;
    final km = RegExp(r'km\s*(\d+)').firstMatch(loc);
    if (km != null) {
      return GeoMath.pointAtM(line, int.parse(km.group(1)!) * 1000.0);
    }
    return pointAlong(line, 0.5);
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

  static double lengthKm(List<LatLng> line) => GeoMath.lengthM(line) / 1000;

  /// Point at [fraction] (0–1) of the way along [line], by distance.
  static LatLng pointAlong(List<LatLng> line, double fraction) {
    if (line.length == 1) return line.first;
    return GeoMath.pointAtM(line, GeoMath.lengthM(line) * fraction.clamp(0.0, 1.0));
  }

  // ── Situation layers ──────────────────────────────────────────────────────

  static MapLineTone toneForStatus(RouteStatus s) {
    switch (s) {
      case RouteStatus.open:
        return MapLineTone.clear;
      case RouteStatus.restricted:
        return MapLineTone.caution;
      case RouteStatus.blocked:
      case RouteStatus.closed:
        return MapLineTone.critical;
    }
  }

  /// One labelled polyline per highway id; unknown ids are skipped.
  static List<MapRoute> routes(Map<String, MapLineTone> tones) => [
        for (final e in tones.entries)
          if (highways.containsKey(e.key))
            MapRoute(label: e.key, points: highways[e.key]!, tone: e.value),
      ];

  /// Spreads vehicles on the same highway so they don't stack.
  static List<MapVehicle> vehicles(Iterable<FleetVehicle> fleet) {
    final seen = <String, int>{};
    final out = <MapVehicle>[];
    for (final v in fleet) {
      final line = highway(v.route);
      if (line == null) continue;
      final n = seen.update(routeIdOf(v.route), (c) => c + 1, ifAbsent: () => 0);
      out.add(MapVehicle(
        id: v.id,
        point: pointAlong(line, 0.3 + 0.25 * (n % 3)),
        risk: v.risk,
        label: '${v.id} · ${routeIdOf(v.route)} → ${v.destination} · ${v.statusLabel}',
      ));
    }
    return out;
  }

  // Demo risk layers. The same shapes are seeded into PostGIS for GeoServer
  // (`backend/geoserver/sql/02_seed.sql`) so local and server analytics agree.

  static const safeZones = [
    MapZone(center: LatLng(26.1800, 91.7500), radiusMeters: 4000, kind: MapZoneKind.safe, label: 'Guwahati relief camp'),
    MapZone(center: nongpoh, radiusMeters: 3000, kind: MapZoneKind.safe, label: 'Nongpoh staging area'),
    MapZone(center: LatLng(25.8900, 93.7400), radiusMeters: 3000, kind: MapZoneKind.safe, label: 'Dimapur safe yard'),
    MapZone(center: jowai, radiusMeters: 2500, kind: MapZoneKind.safe, label: 'Jowai holding yard'),
  ];

  static const floodZones = [
    MapZone(center: LatLng(26.3500, 91.0000), radiusMeters: 18000, kind: MapZoneKind.flood, label: 'Barpeta floodplain'),
    MapZone(center: LatLng(26.2500, 92.3400), radiusMeters: 15000, kind: MapZoneKind.flood, label: 'Morigaon lowlands'),
    MapZone(center: LatLng(26.1300, 91.8000), radiusMeters: 5000, kind: MapZoneKind.flood, label: 'Guwahati low-lying wards'),
  ];

  static const landslideZones = [
    MapZone(center: LatLng(25.5000, 92.0500), radiusMeters: 12000, kind: MapZoneKind.landslide, label: 'Shillong–Jowai slopes'),
    MapZone(center: LatLng(25.4829, 92.1977), radiusMeters: 3000, kind: MapZoneKind.landslide, label: 'Jowai NH-6 cut slopes'),
    MapZone(center: LatLng(25.9450, 91.8750), radiusMeters: 2500, kind: MapZoneKind.landslide, label: 'Umling–Nongpoh slope'),
    MapZone(center: LatLng(25.6600, 94.0500), radiusMeters: 10000, kind: MapZoneKind.landslide, label: 'Kohima ridge'),
    MapZone(center: LatLng(27.4500, 92.1500), radiusMeters: 12000, kind: MapZoneKind.landslide, label: 'Sela approach'),
  ];

  static const infrastructure = [
    MapPoi(point: LatLng(26.1600, 91.7000), kind: MapPoiKind.depot, label: 'Guwahati depot'),
    MapPoi(point: LatLng(26.1900, 91.6600), kind: MapPoiKind.bridge, label: 'Saraighat bridge'),
    MapPoi(point: LatLng(25.9100, 93.7300), kind: MapPoiKind.depot, label: 'Dimapur rail yard'),
    MapPoi(point: LatLng(24.8300, 92.7900), kind: MapPoiKind.depot, label: 'Silchar depot'),
  ];
}
