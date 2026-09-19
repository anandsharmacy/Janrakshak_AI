import 'package:latlong2/latlong.dart';

import '../../../mock_data/models.dart';

/// A rider as seen by the officer dashboards: identity + vehicle + assigned
/// shipment + last known fix. Built from `get_active_riders()` rows and kept
/// current by Realtime changes on `rider_locations` / `rider_profiles`.
class LiveRider {
  final String userId;
  final String fullName;
  final String? officerId;
  final String? phone;
  final String? district;
  final String? vehicleRegistration;
  final String? vehicleType;
  final bool isOnDuty;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? speedKmph;
  final double? headingDeg;
  final int? batteryPercent;
  final bool isMoving;
  final DateTime recordedAt;
  final DateTime? receivedAt;
  final String? shipmentId;
  final String? shipmentNumber;
  final String? shipmentStatus;
  final String? cargoDescription;
  final String? riskLevel;
  final String? originName;
  final String? destinationName;
  final String? routeNumber;
  final DateTime? estimatedArrival;

  const LiveRider({
    required this.userId,
    required this.fullName,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.officerId,
    this.phone,
    this.district,
    this.vehicleRegistration,
    this.vehicleType,
    this.isOnDuty = false,
    this.accuracyM,
    this.speedKmph,
    this.headingDeg,
    this.batteryPercent,
    this.isMoving = false,
    this.receivedAt,
    this.shipmentId,
    this.shipmentNumber,
    this.shipmentStatus,
    this.cargoDescription,
    this.riskLevel,
    this.originName,
    this.destinationName,
    this.routeNumber,
    this.estimatedArrival,
  });

  factory LiveRider.fromRow(Map<String, dynamic> r) => LiveRider(
        userId: r['user_id'] as String,
        fullName: (r['full_name'] as String?)?.trim().isNotEmpty == true
            ? (r['full_name'] as String).trim()
            : 'Rider',
        officerId: r['officer_id'] as String?,
        phone: r['phone'] as String?,
        district: r['district'] as String?,
        vehicleRegistration: r['vehicle_registration'] as String?,
        vehicleType: r['vehicle_type'] as String?,
        isOnDuty: r['is_on_duty'] == true,
        latitude: (r['latitude'] as num).toDouble(),
        longitude: (r['longitude'] as num).toDouble(),
        accuracyM: (r['accuracy_m'] as num?)?.toDouble(),
        speedKmph: (r['speed_kmph'] as num?)?.toDouble(),
        headingDeg: (r['heading_deg'] as num?)?.toDouble(),
        batteryPercent: (r['battery_percent'] as num?)?.toInt(),
        isMoving: r['is_moving'] == true,
        recordedAt: _ts(r['recorded_at']) ?? DateTime.now().toUtc(),
        receivedAt: _ts(r['received_at']),
        shipmentId: r['shipment_id'] as String?,
        shipmentNumber: r['shipment_number'] as String?,
        shipmentStatus: r['shipment_status'] as String?,
        cargoDescription: r['cargo_description'] as String?,
        riskLevel: r['risk_level'] as String?,
        originName: r['origin_name'] as String?,
        destinationName: r['destination_name'] as String?,
        routeNumber: r['route_number'] as String?,
        estimatedArrival: _ts(r['estimated_arrival']),
      );

  /// Applies a Realtime `rider_locations` row. Returns `this` unchanged when
  /// the incoming fix is older than what we already show (out-of-order delivery).
  LiveRider mergeLocation(Map<String, dynamic> rec) {
    final at = _ts(rec['recorded_at']);
    if (at == null || at.isBefore(recordedAt)) return this;
    return _copy(
      latitude: (rec['latitude'] as num?)?.toDouble(),
      longitude: (rec['longitude'] as num?)?.toDouble(),
      accuracyM: (rec['accuracy_m'] as num?)?.toDouble(),
      speedKmph: (rec['speed_kmph'] as num?)?.toDouble(),
      headingDeg: (rec['heading_deg'] as num?)?.toDouble(),
      batteryPercent: (rec['battery_percent'] as num?)?.toInt(),
      isMoving: rec['is_moving'] == true,
      recordedAt: at,
      receivedAt: _ts(rec['received_at']),
      shipmentId: rec.containsKey('shipment_id') ? rec['shipment_id'] as String? : shipmentId,
      clearNumericsIfNull: true,
    );
  }

  /// Applies a Realtime `rider_profiles` row (duty / vehicle changes).
  LiveRider mergeProfile(Map<String, dynamic> rec) => _copy(
        isOnDuty: rec['is_on_duty'] == true,
        vehicleRegistration: rec['vehicle_registration'] as String? ?? vehicleRegistration,
        vehicleType: rec['vehicle_type'] as String? ?? vehicleType,
        phone: rec['phone'] as String? ?? phone,
      );

  LatLng get point => LatLng(latitude, longitude);

  Duration age(DateTime now) => now.toUtc().difference(recordedAt.toUtc());

  bool isStaleAt(DateTime now, {Duration window = const Duration(minutes: 30)}) => age(now) > window;

  /// "Active" = on duty and reporting inside the staleness window.
  bool isActiveAt(DateTime now, {Duration window = const Duration(minutes: 30)}) =>
      isOnDuty && !isStaleAt(now, window: window);

  Priority get riskPriority => switch (riskLevel) {
        'critical' => Priority.critical,
        'high' => Priority.high,
        'medium' || 'moderate' => Priority.medium,
        _ => Priority.low,
      };

  String get vehicleLabel => vehicleRegistration ?? vehicleType ?? 'Vehicle —';

  String get shipmentLabel {
    if (shipmentNumber == null) return 'No shipment assigned';
    final dest = destinationName == null ? '' : ' → $destinationName';
    return '$shipmentNumber$dest';
  }

  String get shipmentStatusLabel => switch (shipmentStatus) {
        'in_transit' => 'In transit',
        'at_risk' => 'At risk',
        null => '—',
        final s => s.isEmpty ? '—' : '${s[0].toUpperCase()}${s.substring(1)}',
      };

  String get speedLabel => speedKmph == null ? '—' : '${speedKmph!.round()} km/h';

  static String ageLabel(Duration d) {
    if (d.isNegative) return 'just now';
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  LiveRider _copy({
    double? latitude,
    double? longitude,
    double? accuracyM,
    double? speedKmph,
    double? headingDeg,
    int? batteryPercent,
    bool? isMoving,
    DateTime? recordedAt,
    DateTime? receivedAt,
    String? shipmentId,
    bool? isOnDuty,
    String? vehicleRegistration,
    String? vehicleType,
    String? phone,
    bool clearNumericsIfNull = false,
  }) {
    final shipmentChanged = shipmentId != this.shipmentId;
    return LiveRider(
      userId: userId,
      fullName: fullName,
      officerId: officerId,
      phone: phone ?? this.phone,
      district: district,
      vehicleRegistration: vehicleRegistration ?? this.vehicleRegistration,
      vehicleType: vehicleType ?? this.vehicleType,
      isOnDuty: isOnDuty ?? this.isOnDuty,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyM: clearNumericsIfNull ? accuracyM : (accuracyM ?? this.accuracyM),
      speedKmph: clearNumericsIfNull ? speedKmph : (speedKmph ?? this.speedKmph),
      headingDeg: clearNumericsIfNull ? headingDeg : (headingDeg ?? this.headingDeg),
      batteryPercent: clearNumericsIfNull ? batteryPercent : (batteryPercent ?? this.batteryPercent),
      isMoving: isMoving ?? this.isMoving,
      recordedAt: recordedAt ?? this.recordedAt,
      receivedAt: receivedAt ?? this.receivedAt,
      shipmentId: shipmentId ?? this.shipmentId,
      // Shipment details are only valid for the shipment they were loaded for.
      shipmentNumber: shipmentChanged ? null : shipmentNumber,
      shipmentStatus: shipmentChanged ? null : shipmentStatus,
      cargoDescription: shipmentChanged ? null : cargoDescription,
      riskLevel: shipmentChanged ? null : riskLevel,
      originName: shipmentChanged ? null : originName,
      destinationName: shipmentChanged ? null : destinationName,
      routeNumber: shipmentChanged ? null : routeNumber,
      estimatedArrival: shipmentChanged ? null : estimatedArrival,
    );
  }

  /// True when a Realtime location row refers to a shipment we have no
  /// details for — the controller re-fetches to fill them in.
  bool needsShipmentRefresh(Map<String, dynamic> rec) {
    if (!rec.containsKey('shipment_id')) return false;
    final incoming = rec['shipment_id'] as String?;
    return incoming != null && incoming != shipmentId;
  }

  static DateTime? _ts(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;
}

/// One breadcrumb from `get_rider_trail()`.
class TrailPoint {
  final LatLng point;
  final double? speedKmph;
  final DateTime recordedAt;
  const TrailPoint({required this.point, required this.recordedAt, this.speedKmph});

  factory TrailPoint.fromRow(Map<String, dynamic> r) => TrailPoint(
        point: LatLng((r['latitude'] as num).toDouble(), (r['longitude'] as num).toDouble()),
        speedKmph: (r['speed_kmph'] as num?)?.toDouble(),
        recordedAt: DateTime.parse(r['recorded_at'] as String).toUtc(),
      );
}
