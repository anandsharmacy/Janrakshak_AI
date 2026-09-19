/// NER Logistics Platform — Data Models
/// All models are plain Dart classes with no backend dependency.
/// These drive every screen in both the Field Officer and Dashboard tracks.

// ── Enums ────────────────────────────────────────────────────────────────────

enum AppRole { field, district, control, rider }

enum RiskLevel { clear, caution, critical }

enum SyncStatus { pending, synced, rejected }

enum Priority { critical, high, medium, low }

enum TaskStatus {
  pending,
  inProgress,
  awaitingVerification,
  completed,
  overdue,
}

enum IncidentType {
  roadBlockage,
  flood,
  landslide,
  accident,
  infraDamage,
  other,
}

enum TripPhase { active, interrupt, calculating, rerouted }

enum AlertSeverity { critical, high, moderate, info }

enum ShipmentStatus { inTransit, delayed, onSchedule }

enum RouteStatus { open, restricted, blocked, closed }

enum RiderTripStatus {
  assigned,
  accepted,
  enRoute,
  paused,
  rerouting,
  arrived,
  completed,
  failed,
  cancelled,
}

enum AssignmentDecision { pending, accepted, rejected, expired }

enum DeliveryProofType { otp, signature, photo, qrCode, geoTag }

enum VehicleIssueType { breakdown, tyre, fuel, mechanical, accident, other }

enum LocationPingStatus { queued, synced, failed }

enum OfflineMapRegionStatus { available, downloading, updateAvailable, unavailable }

class OfflineMapRegion {
  final String id;
  final String name;
  final String coverage;
  final String size;
  final String updatedAt;
  final OfflineMapRegionStatus status;
  final int downloadProgress;

  const OfflineMapRegion({
    required this.id,
    required this.name,
    required this.coverage,
    required this.size,
    required this.updatedAt,
    required this.status,
    this.downloadProgress = 0,
  });

  OfflineMapRegion copyWith({
    OfflineMapRegionStatus? status,
    int? downloadProgress,
    String? updatedAt,
  }) {
    return OfflineMapRegion(
      id: id,
      name: name,
      coverage: coverage,
      size: size,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }
}

class RiderProfile {
  final String name;
  final String riderId;
  final String phone;
  final String language;
  final String vehicleId;
  final String emergencyContact;

  const RiderProfile({
    required this.name,
    required this.riderId,
    required this.phone,
    required this.language,
    required this.vehicleId,
    required this.emergencyContact,
  });
}

class Vehicle {
  final String id;
  final String registrationNumber;
  final String type;
  final String capacity;
  final int fuelPercent;
  final String maintenanceStatus;

  const Vehicle({
    required this.id,
    required this.registrationNumber,
    required this.type,
    required this.capacity,
    required this.fuelPercent,
    required this.maintenanceStatus,
  });
}

class DeliveryAssignment {
  final String id;
  final String tripId;
  final String riderId;
  final String vehicleId;
  final String cargo;
  final Priority priority;
  final String origin;
  final String destination;
  final String recipient;
  final String window;
  final RiskLevel risk;
  final String eta;
  final String distanceRemaining;
  final int progress;
  final RiderTripStatus status;
  final AssignmentDecision decision;
  final bool proofSubmitted;

  const DeliveryAssignment({
    required this.id,
    required this.tripId,
    required this.riderId,
    required this.vehicleId,
    required this.cargo,
    required this.priority,
    required this.origin,
    required this.destination,
    required this.recipient,
    required this.window,
    required this.risk,
    required this.eta,
    required this.distanceRemaining,
    required this.progress,
    required this.status,
    required this.decision,
    this.proofSubmitted = false,
  });

  DeliveryAssignment copyWith({
    RiderTripStatus? status,
    AssignmentDecision? decision,
    int? progress,
    bool? proofSubmitted,
  }) {
    return DeliveryAssignment(
      id: id,
      tripId: tripId,
      riderId: riderId,
      vehicleId: vehicleId,
      cargo: cargo,
      priority: priority,
      origin: origin,
      destination: destination,
      recipient: recipient,
      window: window,
      risk: risk,
      eta: eta,
      distanceRemaining: distanceRemaining,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      decision: decision ?? this.decision,
      proofSubmitted: proofSubmitted ?? this.proofSubmitted,
    );
  }
}

class ProofOfDelivery {
  final String id;
  final DeliveryProofType type;
  final String recipient;
  final DateTime timestamp;
  final String? mediaPath;
  SyncStatus syncStatus;

  ProofOfDelivery({
    required this.id,
    required this.type,
    required this.recipient,
    required this.timestamp,
    this.mediaPath,
    this.syncStatus = SyncStatus.pending,
  });
}

class RiderIssueReport {
  final String id;
  final VehicleIssueType type;
  final String description;
  final Priority severity;
  final DateTime timestamp;
  SyncStatus syncStatus;

  RiderIssueReport({
    required this.id,
    required this.type,
    required this.description,
    required this.severity,
    required this.timestamp,
    this.syncStatus = SyncStatus.pending,
  });
}

class RiderLocationPing {
  final String id;
  final DateTime timestamp;
  final double accuracy;
  final double speed;
  LocationPingStatus status;

  RiderLocationPing({
    required this.id,
    required this.timestamp,
    required this.accuracy,
    required this.speed,
    this.status = LocationPingStatus.queued,
  });
}

// ── Officer ──────────────────────────────────────────────────────────────────

class Officer {
  final String name;
  final String officerId;
  final AppRole role;
  final String roleLabel;
  final String department;
  final String region;
  final String phone;
  final String email;
  final String lastLogin;

  const Officer({
    required this.name,
    required this.officerId,
    required this.role,
    required this.roleLabel,
    required this.department,
    required this.region,
    required this.phone,
    required this.email,
    required this.lastLogin,
  });

  String get initials {
    switch (role) {
      case AppRole.field:
        return 'FO';
      case AppRole.district:
        return 'DO';
      case AppRole.control:
        return 'CO';
      case AppRole.rider:
        return 'RD';
    }
  }
}

// ── Trip ─────────────────────────────────────────────────────────────────────

class TripInfo {
  final String tripId;
  final String consignment;
  final String destination;
  final String origin;

  const TripInfo({
    required this.tripId,
    required this.consignment,
    required this.destination,
    required this.origin,
  });
}

// ── Task ─────────────────────────────────────────────────────────────────────

class FieldTask {
  final String id;
  final String title;
  final String location;
  final Priority priority;
  final String dueTime;
  final String createdTime;
  TaskStatus status;
  String? acceptedAt;

  FieldTask({
    required this.id,
    required this.title,
    required this.location,
    required this.priority,
    required this.dueTime,
    required this.createdTime,
    required this.status,
    this.acceptedAt,
  });
}

// ── Route ────────────────────────────────────────────────────────────────────

class RouteInfo {
  final String id;
  final String name;
  final int score;
  final RiskLevel risk;
  final String condition;
  final int incidentCount;
  final String weather;
  final String updatedAt;
  final RouteDetail detail;

  const RouteInfo({
    required this.id,
    required this.name,
    required this.score,
    required this.risk,
    required this.condition,
    required this.incidentCount,
    required this.weather,
    required this.updatedAt,
    required this.detail,
  });
}

class RouteDetail {
  final String floodRisk;
  final String landslideRisk;
  final String blockage;
  final String history;
  final String recommendedAction;

  const RouteDetail({
    required this.floodRisk,
    required this.landslideRisk,
    required this.blockage,
    required this.history,
    required this.recommendedAction,
  });
}

// ── Shipment ─────────────────────────────────────────────────────────────────

class Shipment {
  final String id;
  final String vehicleId;
  final String cargoType;
  final String origin;
  final String destination;
  final String currentLocation;
  final String route;
  final ShipmentStatus status;
  final RiskLevel risk;
  final String eta;
  final String? delay;

  const Shipment({
    required this.id,
    required this.vehicleId,
    required this.cargoType,
    required this.origin,
    required this.destination,
    required this.currentLocation,
    required this.route,
    required this.status,
    required this.risk,
    required this.eta,
    this.delay,
  });
}

// ── Alert ────────────────────────────────────────────────────────────────────

class AppAlert {
  final String id;
  final AlertSeverity severity;
  final String title;
  final String description;
  final String distance;
  final String time;
  final String recommendedAction;
  final String? incidentId;

  const AppAlert({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    required this.distance,
    required this.time,
    required this.recommendedAction,
    this.incidentId,
  });
}

// ── Incident ─────────────────────────────────────────────────────────────────

class Incident {
  final String id;
  final IncidentType type;
  final String typeLabel;
  final String location;
  final String route;
  final Priority severity;
  final String reporter;
  final String time;
  final bool verified;
  final String assignedOfficer;
  final String statusLabel;

  const Incident({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.location,
    required this.route,
    required this.severity,
    required this.reporter,
    required this.time,
    required this.verified,
    required this.assignedOfficer,
    required this.statusLabel,
  });
}

// ── Nearby incident summary (dashboard) ──────────────────────────────────────

class NearbyIncident {
  final String title;
  final String place;
  final String distance;
  final RiskLevel level;

  const NearbyIncident({
    required this.title,
    required this.place,
    required this.distance,
    required this.level,
  });
}

// ── District summary (control room) ──────────────────────────────────────────

class DistrictSummary {
  final String name;
  final String state;
  final Priority risk;
  final int accessScore;
  final int incidentCount;
  final int criticalCount;
  final int blockedRoutes;
  final String logisticsNote;
  final String statusLabel;

  const DistrictSummary({
    required this.name,
    required this.state,
    required this.risk,
    required this.accessScore,
    required this.incidentCount,
    required this.criticalCount,
    required this.blockedRoutes,
    required this.logisticsNote,
    required this.statusLabel,
  });
}

// ── Fleet vehicle (control room) ─────────────────────────────────────────────

class FleetVehicle {
  final String id;
  final String route;
  final String destination;
  final String statusLabel;
  final Priority risk;
  final String eta;

  const FleetVehicle({
    required this.id,
    required this.route,
    required this.destination,
    required this.statusLabel,
    required this.risk,
    required this.eta,
  });
}

// ── Incident report (field submission) ───────────────────────────────────────

class IncidentReport {
  final String id;
  IncidentType? type;
  String location;
  String gpsCoords;
  String? photoPath;
  String severity;
  String description;
  SyncStatus syncStatus;

  IncidentReport({
    required this.id,
    this.type,
    this.location = '',
    this.gpsCoords = '',
    this.photoPath,
    this.severity = 'moderate',
    this.description = '',
    this.syncStatus = SyncStatus.pending,
  });
}
