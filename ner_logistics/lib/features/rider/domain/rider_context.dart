/// Rider dashboard context returned by `public.get_my_rider_context()`.
class RiderContext {
  final String? fullName;
  final String? officerId;
  final String? phone;
  final String? district;
  final String? vehicleRegistration;
  final String? vehicleType;
  final double? capacityKg;
  final String? emergencyContact;
  final bool isOnDuty;
  final String? activeShipmentId;
  final List<RiderShipment> shipments;

  const RiderContext({
    this.fullName,
    this.officerId,
    this.phone,
    this.district,
    this.vehicleRegistration,
    this.vehicleType,
    this.capacityKg,
    this.emergencyContact,
    this.isOnDuty = false,
    this.activeShipmentId,
    this.shipments = const [],
  });

  /// The shipment location pings should be attached to: the explicitly
  /// active one, else the first open assignment.
  RiderShipment? get activeShipment {
    for (final s in shipments) {
      if (s.id == activeShipmentId) return s;
    }
    return shipments.isEmpty ? null : shipments.first;
  }

  factory RiderContext.fromJson(Map<String, dynamic> j) {
    final profile = (j['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rider = (j['rider'] as Map?)?.cast<String, dynamic>() ?? const {};
    final shipments = (j['shipments'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => RiderShipment.fromJson(m.cast<String, dynamic>()))
        .toList();
    return RiderContext(
      fullName: profile['full_name'] as String?,
      officerId: profile['officer_id'] as String?,
      phone: (rider['phone'] ?? profile['phone']) as String?,
      district: j['district'] as String?,
      vehicleRegistration: rider['vehicle_registration'] as String?,
      vehicleType: rider['vehicle_type'] as String?,
      capacityKg: (rider['capacity_kg'] as num?)?.toDouble(),
      emergencyContact: rider['emergency_contact'] as String?,
      isOnDuty: rider['is_on_duty'] == true,
      activeShipmentId: rider['active_shipment_id'] as String?,
      shipments: shipments,
    );
  }

  RiderContext copyWith({bool? isOnDuty}) => RiderContext(
        fullName: fullName,
        officerId: officerId,
        phone: phone,
        district: district,
        vehicleRegistration: vehicleRegistration,
        vehicleType: vehicleType,
        capacityKg: capacityKg,
        emergencyContact: emergencyContact,
        isOnDuty: isOnDuty ?? this.isOnDuty,
        activeShipmentId: activeShipmentId,
        shipments: shipments,
      );
}

class RiderShipment {
  final String id;
  final String shipmentNumber;
  final String status;
  final String? riskLevel;
  final String? cargoDescription;
  final double? cargoWeightKg;
  final String? origin;
  final String? destination;
  final double? destinationLat;
  final double? destinationLng;
  final String? routeNumber;
  final DateTime? estimatedArrival;
  final String? delayDescription;
  final String? currentLocationText;

  const RiderShipment({
    required this.id,
    required this.shipmentNumber,
    required this.status,
    this.riskLevel,
    this.cargoDescription,
    this.cargoWeightKg,
    this.origin,
    this.destination,
    this.destinationLat,
    this.destinationLng,
    this.routeNumber,
    this.estimatedArrival,
    this.delayDescription,
    this.currentLocationText,
  });

  factory RiderShipment.fromJson(Map<String, dynamic> j) => RiderShipment(
        id: j['id'] as String,
        shipmentNumber: (j['shipment_number'] as String?) ?? '—',
        status: (j['status'] as String?) ?? 'scheduled',
        riskLevel: j['risk_level'] as String?,
        cargoDescription: j['cargo_description'] as String?,
        cargoWeightKg: (j['cargo_weight_kg'] as num?)?.toDouble(),
        origin: j['origin'] as String?,
        destination: j['destination'] as String?,
        destinationLat: (j['destination_lat'] as num?)?.toDouble(),
        destinationLng: (j['destination_lng'] as num?)?.toDouble(),
        routeNumber: j['route_number'] as String?,
        estimatedArrival: j['estimated_arrival'] == null
            ? null
            : DateTime.tryParse(j['estimated_arrival'] as String),
        delayDescription: j['delay_description'] as String?,
        currentLocationText: j['current_location_text'] as String?,
      );

  String get statusLabel => switch (status) {
        'in_transit' => 'In transit',
        'at_risk' => 'At risk',
        _ => status.isEmpty ? '—' : '${status[0].toUpperCase()}${status.substring(1)}',
      };
}
