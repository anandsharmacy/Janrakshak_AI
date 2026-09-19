import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'hazard.dart';
import 'region_data.dart';
import 'taxonomy.dart';

/// Contacts and map metrics/facilities are still illustrative (no backend tables for them yet).
/// Incidents and alerts are live (see feed.dart). Flip this once those sources exist so the banners disappear.
const kSampleData = true;

enum ContactKind {
  fieldOfficer('Field Officers'),
  hospital('Hospitals'),
  police('Police');

  const ContactKind(this.label);
  final String label;
}

class Contact {
  const Contact(this.kind, this.name, this.phone, this.state, this.district, this.pos);
  final ContactKind kind;
  final String name, phone, state, district;
  final LatLng pos;

  Map<String, dynamic> toJson() => {
        'kind': kind.name, 'name': name, 'phone': phone, 'state': state, 'district': district,
        'lat': pos.latitude, 'lng': pos.longitude,
      };
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(ContactKind.values.byName(j['kind']), j['name'],
      j['phone'], j['state'], j['district'], LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()));
}

// Numbers are real national/district helplines (1077 district control room, 108 ambulance, 100 police);
// per-person officer numbers should come from the backend, not be invented here.
const _sites = <(String, String, LatLng)>[
  ('Assam', 'Cachar', LatLng(24.83, 92.78)),
  ('Meghalaya', 'East Khasi Hills', LatLng(25.57, 91.88)),
  ('Odisha', 'Puri', LatLng(19.81, 85.83)),
  ('Manipur', 'Imphal West', LatLng(24.81, 93.94)),
  ('Bihar', 'Darbhanga', LatLng(26.15, 85.90)),
  ('Uttarakhand', 'Nainital', LatLng(29.38, 79.46)),
  ('Sikkim', 'Gangtok', LatLng(27.33, 88.61)),
  ('Arunachal Pradesh', 'Papum Pare', LatLng(27.08, 93.61)),
  ('Andaman & Nicobar Islands', 'South Andaman', LatLng(11.62, 92.73)),
  ('Kerala', 'Wayanad', LatLng(11.69, 76.08)),
];

List<Contact> get seedContacts => [
      for (final (state, district, pos) in _sites) ...[
        Contact(ContactKind.fieldOfficer, 'Field Officer Desk - $district', '1077', state, district, pos),
        Contact(ContactKind.hospital, '$district District Hospital', '108', state, district,
            LatLng(pos.latitude + 0.01, pos.longitude + 0.01)),
        Contact(ContactKind.police, '$district Police Control Room', '100', state, district,
            LatLng(pos.latitude - 0.01, pos.longitude + 0.005)),
      ],
    ];

// ---- Map metrics (sample) ----------------------------------------------------------------

enum MapRange {
  live('Live', 1),
  week('1 Week', 7),
  month('1 Month', 30);

  const MapRange(this.label, this.days);
  final String label;
  final int days;
}

class Metric {
  const Metric(this.value, this.series);
  final double value;
  final List<double> series; // empty for Live

  /// Non-Live: change from first to last point of the aggregated window.
  double get delta => series.length < 2 ? 0 : series.last - series.first;
}

class AreaMetrics {
  const AreaMetrics({
    required this.population,
    required this.risk,
    required this.rainfall,
    required this.wind,
    required this.wave,
    required this.hospitals,
    required this.shelters,
  });
  final Metric population, risk, rainfall, wind;
  final Metric? wave; // coastal only
  final List<String> hospitals, shelters;

  Severity get riskSeverity => switch (risk.value) {
        < 30 => Severity.low,
        < 60 => Severity.moderate,
        < 80 => Severity.high,
        _ => Severity.critical,
      };
}

const _sev = {Severity.low: 8, Severity.moderate: 18, Severity.high: 30, Severity.critical: 42};

/// Deterministic per-location sample data; risk is lifted by nearby live hazards.
AreaMetrics areaMetrics(LatLng p, String? state, String district, MapRange range, List<Hazard> hazards) {
  final seed = (p.latitude * 1000).round() * 31 + (p.longitude * 1000).round();
  final rnd = Random(seed);
  final near = hazards.where((h) => h.center != null && distanceKm(h.center!, p) <= h.radiusKm * 2);
  final lift = near.fold<double>(0, (a, h) => a + _sev[h.severity]!);
  final risk = (25 + rnd.nextInt(25) + lift).clamp(5, 98).toDouble();

  Metric metric(double live) {
    if (range == MapRange.live) return Metric(live, const []);
    final n = range == MapRange.week ? 7 : 15;
    var v = live * (0.7 + rnd.nextDouble() * 0.3);
    final s = <double>[];
    for (var i = 0; i < n; i++) {
      v = (v + (live - v) / (n - i) + (rnd.nextDouble() - 0.5) * live * 0.15).clamp(0, live * 2);
      s.add(v);
    }
    return Metric(s.reduce((a, b) => a + b) / n, s);
  }

  final coastal = state != null && RegionData.coastalStates.contains(state);
  return AreaMetrics(
    population: metric((2000 + rnd.nextInt(30000)) * (1 + lift / 20)),
    risk: metric(risk),
    rainfall: metric(rnd.nextDouble() * 40 + lift * 2),
    wind: metric(8 + rnd.nextDouble() * 25 + lift / 2),
    wave: coastal ? metric(0.5 + rnd.nextDouble() * 2 + lift / 15) : null,
    hospitals: [
      '$district District Hospital',
      'Community Health Centre, $district',
      'Civil Hospital, $district',
    ].take(2 + rnd.nextInt(2)).toList(),
    shelters: [
      'Government Higher Secondary School, $district',
      'Community Hall, $district',
      'Relief Camp Ground, $district',
    ].take(1 + rnd.nextInt(3)).toList(),
  );
}
