import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/features/rider/application/location_policy.dart';
import 'package:ner_logistics/features/rider/domain/rider_location_point.dart';

RiderLocationPoint _pt({
  required double lat,
  required double lng,
  required int seconds,
  double? accuracy,
  String id = 'x',
}) =>
    RiderLocationPoint(
      clientId: id,
      lat: lat,
      lng: lng,
      recordedAt: DateTime.utc(2026, 9, 12, 10, 0).add(Duration(seconds: seconds)),
      accuracyM: accuracy,
    );

void main() {
  const policy = LocationPolicy();
  final base = _pt(lat: 25.9030, lng: 91.8770, seconds: 0, accuracy: 8);

  group('LocationPolicy.evaluate', () {
    test('first fix is always accepted', () {
      expect(policy.evaluate(candidate: base), LocationDecision.accept);
    });

    test('fix inside minInterval is throttled', () {
      final next = _pt(lat: 25.9040, lng: 91.8770, seconds: 4, accuracy: 8);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.skipTooSoon);
    });

    test('moved >= 25 m after >= 10 s is accepted', () {
      // ~111 m north
      final next = _pt(lat: 25.9040, lng: 91.8770, seconds: 12, accuracy: 8);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.accept);
    });

    test('stationary fix after minInterval but before heartbeat is skipped', () {
      final next = _pt(lat: 25.90301, lng: 91.87701, seconds: 30, accuracy: 8);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.skipTooClose);
    });

    test('stationary fix after heartbeat window is accepted as heartbeat', () {
      final next = _pt(lat: 25.9030, lng: 91.8770, seconds: 61, accuracy: 8);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.acceptHeartbeat);
    });

    test('inaccurate fix is skipped while a recent good fix exists', () {
      final next = _pt(lat: 25.9100, lng: 91.8770, seconds: 30, accuracy: 250);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.skipInaccurate);
    });

    test('inaccurate fix is accepted once nothing good arrived for 2 minutes', () {
      final next = _pt(lat: 25.9100, lng: 91.8770, seconds: 150, accuracy: 250);
      expect(policy.evaluate(candidate: next, lastAccepted: base).accepted, isTrue);
    });

    test('out-of-order fix is skipped', () {
      final next = _pt(lat: 25.9100, lng: 91.8770, seconds: -5, accuracy: 8);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.skipOutOfOrder);
    });

    test('paused profile is less eager', () {
      const paused = LocationPolicy.paused();
      final next = _pt(lat: 25.9035, lng: 91.8770, seconds: 40, accuracy: 8); // ~55 m
      expect(paused.evaluate(candidate: next, lastAccepted: base), LocationDecision.skipTooClose);
      expect(policy.evaluate(candidate: next, lastAccepted: base), LocationDecision.accept);
    });
  });

  test('distanceMeters: Guwahati to Shillong is roughly 65 km', () {
    final d = LocationPolicy.distanceMeters(26.1445, 91.7362, 25.5788, 91.8933);
    expect(d, greaterThan(60000));
    expect(d, lessThan(70000));
  });

  test('RiderLocationPoint JSON round-trips through the queue format', () {
    final p = RiderLocationPoint(
      clientId: 'abc',
      lat: 25.9,
      lng: 91.8,
      recordedAt: DateTime.utc(2026, 9, 12, 10, 30, 15),
      accuracyM: 12.5,
      speedKmph: 41,
      headingDeg: 180,
      shipmentId: 'ship-1',
      heartbeat: true,
    );
    final back = RiderLocationPoint.fromJson(p.toJson());
    expect(back.clientId, 'abc');
    expect(back.lat, 25.9);
    expect(back.recordedAt, p.recordedAt);
    expect(back.speedKmph, 41);
    expect(back.shipmentId, 'ship-1');
    expect(back.heartbeat, isTrue);
    expect(p.toRpcJson()['source'], 'mobile-heartbeat');
    expect(p.toRpcJson().containsKey('heartbeat'), isFalse);
  });
}
