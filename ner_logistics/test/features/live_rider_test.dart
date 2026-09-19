import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/features/tracking/application/live_riders_controller.dart';
import 'package:ner_logistics/features/tracking/domain/live_rider.dart';
import 'package:ner_logistics/mock_data/models.dart';

Map<String, dynamic> _row({
  String id = 'u1',
  String recordedAt = '2026-09-12T10:00:00Z',
  bool onDuty = true,
  bool moving = true,
  String? risk = 'high',
}) =>
    {
      'user_id': id,
      'full_name': 'P. Lyngdoh',
      'officer_id': 'NER-RD-1184',
      'phone': '+91 94365 01184',
      'district': 'Ri Bhoi',
      'vehicle_registration': 'ML-05-A-2047',
      'vehicle_type': 'Medium cargo truck',
      'is_on_duty': onDuty,
      'latitude': 25.903,
      'longitude': 91.877,
      'accuracy_m': 12,
      'speed_kmph': 38.4,
      'heading_deg': 165,
      'battery_percent': null,
      'is_moving': moving,
      'recorded_at': recordedAt,
      'received_at': recordedAt,
      'shipment_id': 's1',
      'shipment_number': 'LG-108',
      'shipment_status': 'in_transit',
      'cargo_description': 'Relief kits',
      'risk_level': risk,
      'origin_name': 'Kamrup Metro',
      'destination_name': 'Dimapur',
      'route_number': 'NH-37',
      'estimated_arrival': '2026-09-12T12:00:00Z',
      'is_stale': false,
    };

void main() {
  final now = DateTime.utc(2026, 9, 12, 10, 5);

  test('fromRow parses the get_active_riders shape', () {
    final r = LiveRider.fromRow(_row());
    expect(r.fullName, 'P. Lyngdoh');
    expect(r.vehicleLabel, 'ML-05-A-2047');
    expect(r.shipmentLabel, 'LG-108 → Dimapur');
    expect(r.shipmentStatusLabel, 'In transit');
    expect(r.riskPriority, Priority.high);
    expect(r.speedLabel, '38 km/h');
    expect(r.isStaleAt(now), isFalse);
    expect(r.isActiveAt(now), isTrue);
    expect(r.age(now).inMinutes, 5);
  });

  test('mergeLocation ignores fixes older than the current one', () {
    final r = LiveRider.fromRow(_row());
    final older = r.mergeLocation({
      'user_id': 'u1',
      'latitude': 0.0,
      'longitude': 0.0,
      'recorded_at': '2026-09-12T09:00:00Z',
    });
    expect(identical(older, r), isTrue);
  });

  test('mergeLocation applies a newer fix and keeps shipment details', () {
    final r = LiveRider.fromRow(_row());
    final newer = r.mergeLocation({
      'user_id': 'u1',
      'latitude': 25.95,
      'longitude': 91.9,
      'speed_kmph': 0,
      'heading_deg': null,
      'is_moving': false,
      'recorded_at': '2026-09-12T10:04:00Z',
      'received_at': '2026-09-12T10:04:01Z',
      'shipment_id': 's1',
    });
    expect(newer.latitude, 25.95);
    expect(newer.isMoving, isFalse);
    expect(newer.headingDeg, isNull);
    expect(newer.shipmentNumber, 'LG-108');
    expect(newer.needsShipmentRefresh({'shipment_id': 's2'}), isTrue);
    expect(newer.needsShipmentRefresh({'shipment_id': 's1'}), isFalse);
  });

  test('a new shipment id clears the stale shipment details', () {
    final r = LiveRider.fromRow(_row());
    final changed = r.mergeLocation({
      'user_id': 'u1',
      'latitude': 25.95,
      'longitude': 91.9,
      'recorded_at': '2026-09-12T10:04:00Z',
      'shipment_id': 's2',
    });
    expect(changed.shipmentId, 's2');
    expect(changed.shipmentNumber, isNull);
  });

  test('mergeProfile updates duty and vehicle', () {
    final r = LiveRider.fromRow(_row()).mergeProfile({'user_id': 'u1', 'is_on_duty': false});
    expect(r.isOnDuty, isFalse);
    expect(r.vehicleRegistration, 'ML-05-A-2047');
  });

  test('staleness uses the window', () {
    final r = LiveRider.fromRow(_row(recordedAt: '2026-09-12T09:00:00Z'));
    expect(r.isStaleAt(now), isTrue);
    expect(r.isStaleAt(now, window: const Duration(hours: 2)), isFalse);
    expect(LiveRider.ageLabel(r.age(now)), '1 h ago');
    expect(LiveRider.ageLabel(const Duration(seconds: 10)), 'just now');
    expect(LiveRider.ageLabel(const Duration(minutes: 7)), '7 min ago');
  });

  test('LiveRidersState sorts active riders first and counts correctly', () {
    final active = LiveRider.fromRow(_row(id: 'a'));
    final stale = LiveRider.fromRow(_row(id: 'b', recordedAt: '2026-09-12T08:00:00Z'));
    final offDuty = LiveRider.fromRow(_row(id: 'c', onDuty: false, moving: false, recordedAt: '2026-09-12T10:03:00Z'));
    final state = LiveRidersState(
      riders: {'b': stale, 'c': offDuty, 'a': active},
      feed: LiveFeedStatus.live,
      now: now,
    );
    expect(state.sorted.map((r) => r.userId), ['a', 'c', 'b']);
    expect(state.activeCount, 1);
    expect(state.movingCount, 1);
    expect(state.staleCount, 1);
    expect(state.total, 3);
  });
}
