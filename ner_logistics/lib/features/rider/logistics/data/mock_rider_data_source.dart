import 'package:latlong2/latlong.dart';

import '../domain/rider.dart';
import '../domain/rider_data_repository.dart';

/// DEMO rider data behind [RiderDataRepository].
///
/// Holds the seven-rider demo dataset, one road corridor per rider, the demo
/// incident and the session → rider mapping. Nothing here is referenced by
/// UI code; replace this class with an API-backed repository and the screens
/// stay unchanged.
class MockRiderDataSource implements RiderDataRepository {
  const MockRiderDataSource();

  // ── Dataset ───────────────────────────────────────────────────────────────
  //
  // RiderID,RiderName,Phone,State,District,VehicleType,Rating,Status
  static const riderCsv = '''
R001,Rohan Das,9876543210,Assam,Kamrup Metropolitan,Bike,4.8,Active
R002,Bidyut Konwar,9876543211,Assam,Dibrugarh,Scooter,4.5,Active
R003,Lalrinawma Ralte,9876543212,Mizoram,Aizawl,Bike,4.7,Active
R004,Kevichusa Angami,9876543213,Nagaland,Kohima,Bike,4.6,Inactive
R005,Ibemhal Singh,9876543214,Manipur,Imphal West,Scooter,4.9,Active
R006,Banlum Khonglah,9876543215,Meghalaya,East Khasi Hills,Bike,4.4,Active
R007,Subrata Debbarma,9876543216,Tripura,West Tripura,Bike,4.3,Active
''';

  /// Signed-in accounts → dataset rider. Keys are lower-case officer IDs or
  /// emails. Accounts not listed fall back to a stable hash of their user id
  /// (see [riderForUser]) so any rider login still resolves to one row.
  static const identityToRiderId = <String, String>{
    'ner-rd-1184': 'R001',
    'p.lyngdoh@ner.gov.in': 'R001',
  };

  static final List<Rider> _riders = _parse(riderCsv);

  static List<Rider> _parse(String csv) {
    final out = <Rider>[];
    for (final raw in csv.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final f = line.split(',');
      final id = f[0].trim();
      final route = _routes[id];
      final start = route?.start ?? _districtCentre[id]!;
      out.add(Rider(
        id: id,
        name: f[1].trim(),
        callsign: Rider.callsignFor(id),
        phone: f[2].trim(),
        state: f[3].trim(),
        district: f[4].trim(),
        vehicleType: f[5].trim(),
        rating: double.parse(f[6].trim()),
        status: RiderStatusLabel.parse(f[7]),
        latitude: start.latitude,
        longitude: start.longitude,
        routeId: route?.id,
        origin: route?.origin,
        destination: route?.destination,
        currentRoute: route?.waypoints ?? const [],
      ));
    }
    return out;
  }

  // ── Geometry ──────────────────────────────────────────────────────────────

  /// NH-6 corridor Guwahati → Shillong, hand-placed along the road alignment
  /// (Khanapara, Jorabat, Byrnihat, Umling, Nongpoh, Umsning, Umiam, Mawlai).
  static const primaryCorridor = <LatLng>[
    LatLng(26.1445, 91.7362), // 0  Guwahati depot
    LatLng(26.1250, 91.7900), // 1  Beltola
    LatLng(26.1120, 91.8200), // 2  Khanapara
    LatLng(26.1030, 91.8740), // 3  Jorabat
    LatLng(26.0350, 91.8720), // 4  Byrnihat
    LatLng(25.9750, 91.8700), // 5  Umling
    LatLng(25.9030, 91.8770), // 6  Nongpoh
    LatLng(25.7900, 91.8900), // 7  Umsning
    LatLng(25.6600, 91.8930), // 8  Umiam  ← demo incident
    LatLng(25.6100, 91.8900), // 9  Mawlai
    LatLng(25.5788, 91.8933), // 10 Shillong depot
  ];

  /// Alternate: leaves NH-6 south of Umsning, runs east through Umroi and
  /// rejoins at Shillong, so the Umiam stretch is never entered.
  static const primaryAlternate = <LatLng>[
    LatLng(25.7250, 91.8905), // branch point on NH-6, before Umiam
    LatLng(25.7150, 91.9300),
    LatLng(25.6900, 91.9600), // Umroi
    LatLng(25.6400, 91.9500),
    LatLng(25.6000, 91.9200),
    LatLng(25.5788, 91.8933), // Shillong depot
  ];

  static const _incidentWaypointIndex = 8;

  static const _routes = <String, RiderRoute>{
    'R001': RiderRoute(
      id: 'NER-12',
      riderId: 'R001',
      origin: 'Guwahati',
      destination: 'Shillong Depot',
      waypoints: primaryCorridor,
      alternate: primaryAlternate,
    ),
    // Secondary riders: short district tracks. Straight lines are acceptable
    // here — they are context on the primary rider's map, not the demo focus.
    'R002': RiderRoute(id: 'NER-31', riderId: 'R002', origin: 'Dibrugarh', destination: 'Mohanbari',
        waypoints: [LatLng(27.4728, 94.9120), LatLng(27.4830, 95.0170)]),
    'R003': RiderRoute(id: 'NER-44', riderId: 'R003', origin: 'Aizawl', destination: 'Durtlang',
        waypoints: [LatLng(23.7271, 92.7176), LatLng(23.7560, 92.7300)]),
    'R005': RiderRoute(id: 'NER-52', riderId: 'R005', origin: 'Imphal', destination: 'Lamphelpat',
        waypoints: [LatLng(24.8170, 93.9368), LatLng(24.7920, 93.9120)]),
    'R006': RiderRoute(id: 'NER-18', riderId: 'R006', origin: 'Shillong', destination: 'Mawlai',
        waypoints: [LatLng(25.5788, 91.8933), LatLng(25.6100, 91.8900)]),
    'R007': RiderRoute(id: 'NER-61', riderId: 'R007', origin: 'Agartala', destination: 'Khayerpur',
        waypoints: [LatLng(23.8315, 91.2868), LatLng(23.8610, 91.3170)]),
  };

  /// Parked position for riders with no route (the inactive rider).
  static const _districtCentre = <String, LatLng>{
    'R004': LatLng(25.6751, 94.1086), // Kohima
  };

  static final _incidents = <String, RouteIncident>{
    'NER-12': RouteIncident(
      id: 'INC-NH6-UMIAM',
      routeId: 'NER-12',
      waypointIndex: _incidentWaypointIndex,
      point: primaryCorridor[_incidentWaypointIndex],
      title: 'Landslide debris on NH-6',
      location: 'Umiam, Ri Bhoi',
      description: 'Both lanes obstructed near the Umiam bridge approach. '
          'Clearance crew dispatched; no timeline for reopening.',
    ),
  };

  // ── RiderDataRepository ──────────────────────────────────────────────────

  @override
  Future<List<Rider>> fetchRiders() async => List.unmodifiable(_riders);

  @override
  Future<Rider?> riderForUser({
    required String userId,
    String? officerId,
    String? email,
  }) async {
    final byId = _find(officerId);
    if (byId != null) return byId;
    for (final key in [officerId, email]) {
      final mapped = key == null ? null : identityToRiderId[key.trim().toLowerCase()];
      final rider = _find(mapped);
      if (rider != null) return rider;
    }
    // Unknown account: pick a stable dataset row from the user id so the
    // same login always sees the same rider.
    final active = _riders.where((r) => r.isActive).toList();
    if (active.isEmpty) return null;
    return active[userId.hashCode.abs() % active.length];
  }

  static Rider? _find(String? riderId) {
    if (riderId == null) return null;
    final key = riderId.trim().toUpperCase();
    for (final r in _riders) {
      if (r.id == key) return r;
    }
    return null;
  }

  @override
  Future<RiderRoute?> assignedRoute(String riderId) async => _routes[riderId];

  @override
  Future<RouteIncident?> incidentOnRoute(String routeId) async => _incidents[routeId];
}
