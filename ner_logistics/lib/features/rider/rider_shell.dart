import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/connectivity_provider.dart';
import '../../mock_data/mock_officers.dart';
import '../../mock_data/mock_repository.dart';
import '../../mock_data/models.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../features/profile/profile_sheet.dart';
import '../auth/application/auth_controller.dart';
import 'application/rider_tracking_controller.dart';
import 'data/rider_repository.dart';
import 'logistics/application/rider_logistics_service.dart';
import 'rider_dashboard.dart';
import 'rider_drawer.dart';

/// RiderShell — top-level widget for the Logistics Rider track.
///
/// Identity comes from Supabase Auth (`currentProfileProvider`), vehicle and
/// assigned shipments from `get_my_rider_context`, and live location sharing
/// from [riderTrackingProvider]. Trip actions keep the existing demo state
/// but also drive the real tracker: Start → share, Pause → low power,
/// Resume → share, Arrived → low power.
class RiderShell extends ConsumerStatefulWidget {
  final VoidCallback onSignOut;

  const RiderShell({super.key, required this.onSignOut});

  @override
  ConsumerState<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends ConsumerState<RiderShell> {
  RiderNav _nav = RiderNav.dashboard;
  bool _drawerOpen = false;
  bool _profileOpen = false;

  String get _title => switch (_nav) {
        RiderNav.dashboard => 'Rider Dashboard',
        RiderNav.deliveries => 'My Deliveries',
        RiderNav.trip => 'Active Trip',
        RiderNav.routeAlerts => 'Route & Alerts',
        RiderNav.report => 'Report Issue',
        RiderNav.history => 'Delivery History',
        RiderNav.queue => 'Offline Queue',
      };

  String _subtitle(Officer officer, String? vehicle, RiderTrackingState tracking) => switch (_nav) {
        RiderNav.dashboard => '${officer.name} · ${vehicle ?? 'vehicle not set'}',
        RiderNav.deliveries => '2 assignments · ${officer.region}',
        RiderNav.trip => _tripSubtitle(tracking),
        RiderNav.routeAlerts => 'Route safety · live advisories',
        RiderNav.report => 'Saves offline first · GPS tagged',
        RiderNav.history => 'Completed deliveries · this month',
        RiderNav.queue => tracking.queued > 0
            ? '${tracking.queued} positions queued · sync when online'
            : 'Queued actions · sync when online',
      };

  /// Route id and destination come from the rider logistics service so the
  /// header matches the trip panel; the old static copy is the fallback.
  String _tripSubtitle(RiderTrackingState tracking) {
    final rider = ref.watch(riderLogisticsProvider).rider;
    final trip = rider?.routeId == null ? 'TRP-R-4821' : 'Route ${rider!.routeId}';
    if (tracking.isSharing) return '$trip · sharing live location';
    return '$trip · ${rider?.destination == null ? 'medicines to Nongpoh' : 'to ${rider!.destination}'}';
  }

  RiderTrackingController get _tracker => ref.read(riderTrackingProvider.notifier);

  String? get _activeShipmentId => ref.read(riderContextProvider).valueOrNull?.activeShipment?.id;

  Future<void> _startSharing() => _tracker.start(shipmentId: _activeShipmentId);

  Future<void> _signOut() async {
    // Never leave a foreground service running for a signed-out account.
    await _tracker.stop();
    widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(mockRepositoryProvider);
    final tracking = ref.watch(riderTrackingProvider);
    final riderCtx = ref.watch(riderContextProvider).valueOrNull;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final officer = ref.watch(currentProfileProvider)?.toOfficer() ?? riderOfficer;
    final offline = appState.isOffline || !online;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F1),
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: _title,
                subtitle: _subtitle(officer, riderCtx?.vehicleRegistration, tracking),
                roleInitials: 'RD',
                alertCount: appState.activeRiderAssignment?.risk == RiskLevel.critical ? 1 : 0,
                isOffline: offline,
                onMenu: () => setState(() => _drawerOpen = true),
                onBell: () => setState(() => _nav = RiderNav.routeAlerts),
                onAvatar: () => setState(() => _profileOpen = true),
              ),
              OfflineBanner(isOffline: offline),
              Expanded(child: _buildBody(appState, tracking, riderCtx, online)),
            ],
          ),
          if (_drawerOpen)
            Positioned.fill(
              child: RiderDrawer(
                current: _nav,
                officer: officer,
                queueCount: appState.riderQueueCount + tracking.queued,
                onNavigate: (nav) => setState(() => _nav = nav),
                onClose: () => setState(() => _drawerOpen = false),
                onSignOut: _signOut,
              ),
            ),
          if (_profileOpen)
            Positioned.fill(
              child: ProfileSheet(
                role: AppRole.rider,
                officer: officer,
                onClose: () => setState(() => _profileOpen = false),
                onSignOut: _signOut,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    MockAppState appState,
    RiderTrackingState tracking,
    riderCtx,
    bool online,
  ) {
    final repository = ref.read(mockRepositoryProvider.notifier);
    return RiderDashboard(
      section: _nav,
      appState: appState,
      tracking: tracking,
      riderContext: riderCtx,
      online: online,
      onNavigate: (nav) => setState(() => _nav = nav),
      onToggleOffline: repository.toggleOffline,
      onStartTrip: () {
        repository.setRiderTripStatus(RiderTripStatus.enRoute);
        _startSharing();
      },
      onPauseTrip: () {
        repository.setRiderTripStatus(RiderTripStatus.paused);
        _tracker.setPaused(true);
      },
      onResumeTrip: () {
        repository.setRiderTripStatus(RiderTripStatus.enRoute);
        if (tracking.isSharing) {
          _tracker.setPaused(false);
        } else {
          _startSharing();
        }
      },
      onAccept: () => repository.decideAssignment('ASN-4828', AssignmentDecision.accepted),
      onComplete: () {
        repository.setRiderTripStatus(RiderTripStatus.arrived);
        _tracker.setPaused(true);
      },
      onAddProof: () {
        repository.queueProof(ProofOfDelivery(
          id: 'POD-${DateTime.now().millisecondsSinceEpoch}',
          type: DeliveryProofType.photo,
          recipient: 'Dr. M. Khongwir',
          timestamp: DateTime.now(),
        ));
        repository.markRiderProofSubmitted();
      },
      onReportIssue: () => repository.queueIssue(
            RiderIssueReport(
              id: 'ISS-${DateTime.now().millisecondsSinceEpoch}',
              type: VehicleIssueType.other,
              description: 'Road condition reported from active route',
              severity: Priority.medium,
              timestamp: DateTime.now(),
            ),
          ),
      onDownloadMap: (regionId) {
        repository.startOfflineMapDownload(regionId);
        repository.completeOfflineMapDownload(regionId);
      },
      onRefreshMap: repository.refreshOfflineMap,
      onToggleSharing: () {
        if (tracking.isSharing) {
          _tracker.stop();
        } else {
          _startSharing();
        }
      },
      onCheckIn: _tracker.captureNow,
      onRetrySync: _tracker.retryNow,
      onDismissTrackingError: _tracker.clearError,
    );
  }
}
