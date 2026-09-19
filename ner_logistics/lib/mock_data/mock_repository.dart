import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_alerts.dart';
import 'mock_deliveries.dart';
import 'mock_officers.dart' as officer_mocks;
import 'mock_offline_maps.dart';
import 'mock_riders.dart' as rider_mocks;
import 'mock_vehicles.dart' as vehicle_mocks;
import 'models.dart';

/// Shared in-memory data source for the frontend demo.
///
/// This intentionally has no persistence or network dependency. It provides a
/// single local source of truth for screens that need to coordinate state.
class MockAppState {
  final Officer activeOfficer;
  final TripInfo activeTrip;
  final TripPhase tripPhase;
  final bool postReroute;
  final bool riskUpgraded;
  final bool isOffline;
  final List<AppAlert> alerts;
  final List<IncidentReport> reports;
  final RiderProfile activeRider;
  final Vehicle riderVehicle;
  final List<DeliveryAssignment> riderAssignments;
  final List<ProofOfDelivery> queuedProofs;
  final List<RiderIssueReport> queuedIssues;
  final List<RiderLocationPing> queuedLocationPings;
  final List<OfflineMapRegion> offlineMapRegions;

  const MockAppState({
    required this.activeOfficer,
    required this.activeTrip,
    required this.tripPhase,
    required this.postReroute,
    required this.riskUpgraded,
    required this.isOffline,
    required this.alerts,
    required this.reports,
    required this.activeRider,
    required this.riderVehicle,
    required this.riderAssignments,
    required this.queuedProofs,
    required this.queuedIssues,
    required this.queuedLocationPings,
    required this.offlineMapRegions,
  });

  factory MockAppState.initial() => MockAppState(
      activeOfficer: officer_mocks.fieldOfficer,
      activeTrip: officer_mocks.activeTrip,
        tripPhase: TripPhase.active,
        postReroute: false,
        riskUpgraded: false,
        isOffline: false,
        alerts: List.unmodifiable(mockAlerts),
        reports: const [],
        activeRider: rider_mocks.activeRider,
        riderVehicle: vehicle_mocks.riderVehicle,
        riderAssignments: List.unmodifiable(mockRiderDeliveries),
        queuedProofs: const [],
        queuedIssues: const [],
        queuedLocationPings: const [],
        offlineMapRegions: List.unmodifiable(mockOfflineMapRegions),
      );

  int get criticalAlertCount =>
      alerts.where((alert) => alert.severity == AlertSeverity.critical).length;

  int get pendingReportCount => reports
      .where((report) => report.syncStatus == SyncStatus.pending)
      .length;

  DeliveryAssignment? get activeRiderAssignment => riderAssignments
      .cast<DeliveryAssignment?>()
      .firstWhere(
        (assignment) => assignment!.status != RiderTripStatus.completed &&
            assignment.status != RiderTripStatus.cancelled,
        orElse: () => null,
      );

  int get riderQueueCount => queuedProofs.length +
      queuedIssues.length +
      queuedLocationPings.length;

    OfflineMapRegion? get activeOfflineMap => offlineMapRegions
      .where((region) => region.status == OfflineMapRegionStatus.available)
      .firstOrNull;

  MockAppState copyWith({
    TripPhase? tripPhase,
    bool? postReroute,
    bool? riskUpgraded,
    bool? isOffline,
    List<AppAlert>? alerts,
    List<IncidentReport>? reports,
    List<DeliveryAssignment>? riderAssignments,
    List<ProofOfDelivery>? queuedProofs,
    List<RiderIssueReport>? queuedIssues,
    List<RiderLocationPing>? queuedLocationPings,
    List<OfflineMapRegion>? offlineMapRegions,
  }) {
    return MockAppState(
      activeOfficer: activeOfficer,
      activeTrip: activeTrip,
      tripPhase: tripPhase ?? this.tripPhase,
      postReroute: postReroute ?? this.postReroute,
      riskUpgraded: riskUpgraded ?? this.riskUpgraded,
      isOffline: isOffline ?? this.isOffline,
      alerts: alerts ?? this.alerts,
      reports: reports ?? this.reports,
      activeRider: activeRider,
      riderVehicle: riderVehicle,
      riderAssignments: riderAssignments ?? this.riderAssignments,
      queuedProofs: queuedProofs ?? this.queuedProofs,
      queuedIssues: queuedIssues ?? this.queuedIssues,
      queuedLocationPings: queuedLocationPings ?? this.queuedLocationPings,
      offlineMapRegions: offlineMapRegions ?? this.offlineMapRegions,
    );
  }
}

class MockRepository extends StateNotifier<MockAppState> {
  MockRepository() : super(MockAppState.initial());

  void setOffline(bool value) {
    state = state.copyWith(isOffline: value);
  }

  void toggleOffline() {
    setOffline(!state.isOffline);
  }

  void triggerRisk() {
    if (state.postReroute || state.tripPhase != TripPhase.active) return;
    state = state.copyWith(
      tripPhase: TripPhase.interrupt,
      riskUpgraded: false,
    );
  }

  void setTripPhase(TripPhase phase) {
    state = state.copyWith(tripPhase: phase);
  }

  void dismissRisk() {
    state = state.copyWith(
      tripPhase: TripPhase.active,
      riskUpgraded: true,
    );
  }

  void completeReroute() {
    state = state.copyWith(
      tripPhase: TripPhase.active,
      postReroute: true,
      riskUpgraded: false,
      alerts: state.alerts
          .where((alert) => alert.severity != AlertSeverity.critical)
          .toList(growable: false),
    );
  }

  void acknowledgeAlert(String id) {
    state = state.copyWith(
      alerts: state.alerts.where((alert) => alert.id != id).toList(growable: false),
    );
  }

  void queueReport(IncidentReport report) {
    final reports = [...state.reports, report];
    state = state.copyWith(reports: List.unmodifiable(reports));
  }

  void markReportSynced(String reportId) {
    final reports = state.reports.map((report) {
      if (report.id != reportId) return report;
      report.syncStatus = SyncStatus.synced;
      return report;
    }).toList(growable: false);
    state = state.copyWith(reports: List.unmodifiable(reports));
  }

  void decideAssignment(String assignmentId, AssignmentDecision decision) {
    final assignments = state.riderAssignments.map((assignment) {
      if (assignment.id != assignmentId) return assignment;
      return assignment.copyWith(
        decision: decision,
        status: decision == AssignmentDecision.accepted
            ? RiderTripStatus.accepted
            : assignment.status,
      );
    }).toList(growable: false);
    state = state.copyWith(riderAssignments: List.unmodifiable(assignments));
  }

  void setRiderTripStatus(RiderTripStatus status) {
    final active = state.activeRiderAssignment;
    if (active == null) return;
    final assignments = state.riderAssignments.map((assignment) {
      return assignment.id == active.id
          ? assignment.copyWith(status: status)
          : assignment;
    }).toList(growable: false);
    state = state.copyWith(riderAssignments: List.unmodifiable(assignments));
  }

  void queueProof(ProofOfDelivery proof) {
    state = state.copyWith(
      queuedProofs: List.unmodifiable([...state.queuedProofs, proof]),
    );
  }

  void queueIssue(RiderIssueReport issue) {
    state = state.copyWith(
      queuedIssues: List.unmodifiable([...state.queuedIssues, issue]),
    );
  }

  void queueLocationPing(RiderLocationPing ping) {
    state = state.copyWith(
      queuedLocationPings:
          List.unmodifiable([...state.queuedLocationPings, ping]),
    );
  }

  void startOfflineMapDownload(String regionId) {
    final regions = state.offlineMapRegions.map((region) {
      if (region.id != regionId) return region;
      return region.copyWith(
        status: OfflineMapRegionStatus.downloading,
        downloadProgress: 20,
      );
    }).toList(growable: false);
    state = state.copyWith(offlineMapRegions: List.unmodifiable(regions));
  }

  void completeOfflineMapDownload(String regionId) {
    final regions = state.offlineMapRegions.map((region) {
      if (region.id != regionId) return region;
      return region.copyWith(
        status: OfflineMapRegionStatus.available,
        downloadProgress: 100,
        updatedAt: 'Just now',
      );
    }).toList(growable: false);
    state = state.copyWith(offlineMapRegions: List.unmodifiable(regions));
  }

  void refreshOfflineMap(String regionId) {
    startOfflineMapDownload(regionId);
    completeOfflineMapDownload(regionId);
  }

  void markRiderProofSubmitted() {
    final active = state.activeRiderAssignment;
    if (active == null) return;
    final assignments = state.riderAssignments.map((assignment) {
      return assignment.id == active.id
          ? assignment.copyWith(proofSubmitted: true)
          : assignment;
    }).toList(growable: false);
    state = state.copyWith(riderAssignments: List.unmodifiable(assignments));
  }

  void resetDemo() {
    state = MockAppState.initial();
  }
}

final mockRepositoryProvider =
    StateNotifierProvider<MockRepository, MockAppState>(
  (ref) => MockRepository(),
);
