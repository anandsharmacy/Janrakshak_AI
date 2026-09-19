import 'dart:math' as math;

import '../domain/rider_location_point.dart';

/// Why a fix was accepted or dropped. Surfaced in the rider's tracking card
/// and in tests; never blocks the stream.
enum LocationDecision {
  /// First fix, or moved far enough / long enough since the last upload.
  accept,

  /// Heartbeat: nothing moved but officers should still see "seen just now".
  acceptHeartbeat,

  /// Too close to the last accepted fix and too soon: skip to save battery/data.
  skipTooClose,

  /// Fix arrived faster than [LocationPolicy.minInterval] allows.
  skipTooSoon,

  /// Accuracy worse than [LocationPolicy.maxAccuracyM] and a good fix is recent.
  skipInaccurate,

  /// Device clock went backwards relative to the last accepted fix.
  skipOutOfOrder,
}

/// Pure decision logic for when a GPS fix is worth uploading.
///
/// Defaults balance a moving truck on NER highways against battery/data use:
///   * upload when moved ≥ 25 m AND ≥ 10 s passed since the last upload
///   * always upload after 60 s (heartbeat) so staleness on the map is honest
///   * ignore fixes worse than 100 m unless we have had nothing for 2 minutes
///
/// This class is intentionally free of Flutter/plugin dependencies so it can
/// be unit-tested and tuned without a device.
class LocationPolicy {
  final double minDistanceM;
  final Duration minInterval;
  final Duration heartbeat;
  final double maxAccuracyM;
  final Duration acceptInaccurateAfter;

  const LocationPolicy({
    this.minDistanceM = 25,
    this.minInterval = const Duration(seconds: 10),
    this.heartbeat = const Duration(seconds: 60),
    this.maxAccuracyM = 100,
    this.acceptInaccurateAfter = const Duration(minutes: 2),
  });

  /// Lower-frequency profile for paused trips / stationary riders.
  const LocationPolicy.paused()
      : minDistanceM = 100,
        minInterval = const Duration(seconds: 30),
        heartbeat = const Duration(minutes: 3),
        maxAccuracyM = 150,
        acceptInaccurateAfter = const Duration(minutes: 5);

  LocationDecision evaluate({
    required RiderLocationPoint candidate,
    RiderLocationPoint? lastAccepted,
  }) {
    if (lastAccepted == null) return LocationDecision.accept;

    final elapsed = candidate.recordedAt.difference(lastAccepted.recordedAt);
    if (elapsed.isNegative) return LocationDecision.skipOutOfOrder;

    final inaccurate = (candidate.accuracyM ?? 0) > maxAccuracyM;
    if (inaccurate && elapsed < acceptInaccurateAfter) {
      return LocationDecision.skipInaccurate;
    }

    if (elapsed >= heartbeat) return LocationDecision.acceptHeartbeat;
    if (elapsed < minInterval) return LocationDecision.skipTooSoon;

    final moved = distanceMeters(lastAccepted.lat, lastAccepted.lng, candidate.lat, candidate.lng);
    if (moved >= minDistanceM) return LocationDecision.accept;
    return LocationDecision.skipTooClose;
  }

  /// Haversine great-circle distance in metres.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}

extension LocationDecisionX on LocationDecision {
  bool get accepted => this == LocationDecision.accept || this == LocationDecision.acceptHeartbeat;

  String get label => switch (this) {
        LocationDecision.accept => 'Position updated',
        LocationDecision.acceptHeartbeat => 'Heartbeat sent',
        LocationDecision.skipTooClose => 'Stationary — skipped',
        LocationDecision.skipTooSoon => 'Throttled',
        LocationDecision.skipInaccurate => 'Weak GPS — skipped',
        LocationDecision.skipOutOfOrder => 'Clock skew — skipped',
      };
}
