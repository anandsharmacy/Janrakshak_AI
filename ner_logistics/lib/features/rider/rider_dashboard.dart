import 'package:flutter/material.dart';
import '../../core/demo/demo_mode.dart';
import '../../mock_data/mock_repository.dart';
import '../../mock_data/models.dart';
import '../ml/presentation/ml_widgets.dart';
import '../../shared/widgets/widgets.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'application/rider_tracking_controller.dart';
import 'domain/rider_context.dart';
import 'logistics/presentation/rider_logistics_panel.dart';
import 'presentation/live_sharing_card.dart';
import 'rider_drawer.dart';
import 'rider_route_panel.dart';

class RiderDashboard extends StatelessWidget {
  final RiderNav section;
  final MockAppState appState;
  final ValueChanged<RiderNav> onNavigate;
  final VoidCallback onToggleOffline;
  final VoidCallback onStartTrip;
  final VoidCallback onPauseTrip;
  final VoidCallback onResumeTrip;
  final VoidCallback onAccept;
  final VoidCallback onComplete;
  final VoidCallback onAddProof;
  final VoidCallback onReportIssue;
  final ValueChanged<String> onDownloadMap;
  final ValueChanged<String> onRefreshMap;

  // Live location sharing (Supabase-backed)
  final RiderTrackingState tracking;
  final RiderContext? riderContext;
  final bool online;
  final VoidCallback onToggleSharing;
  final VoidCallback onCheckIn;
  final VoidCallback onRetrySync;
  final VoidCallback onDismissTrackingError;

  const RiderDashboard({
    super.key,
    required this.section,
    required this.appState,
    required this.onNavigate,
    required this.onToggleOffline,
    required this.onStartTrip,
    required this.onPauseTrip,
    required this.onResumeTrip,
    required this.onAccept,
    required this.onComplete,
    required this.onAddProof,
    required this.onReportIssue,
    required this.onDownloadMap,
    required this.onRefreshMap,
    required this.tracking,
    required this.riderContext,
    required this.online,
    required this.onToggleSharing,
    required this.onCheckIn,
    required this.onRetrySync,
    required this.onDismissTrackingError,
  });

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case RiderNav.dashboard:
        return _DashboardHome(
          state: appState,
          onNavigate: onNavigate,
          onStartTrip: onStartTrip,
          onAddProof: onAddProof,
          onReportIssue: onReportIssue,
          onToggleOffline: onToggleOffline,
          onDownloadMap: onDownloadMap,
          onRefreshMap: onRefreshMap,
          tracking: tracking,
          riderContext: riderContext,
          online: online,
          onToggleSharing: onToggleSharing,
          onCheckIn: onCheckIn,
          onRetrySync: onRetrySync,
          onDismissTrackingError: onDismissTrackingError,
        );
      case RiderNav.deliveries:
        return _DeliveriesView(
            state: appState, onAccept: onAccept, onNavigate: onNavigate);
      case RiderNav.trip:
        return _ActiveTripView(
          state: appState,
          onPause: onPauseTrip,
          onResume: onResumeTrip,
          onComplete: onComplete,
          onProof: onAddProof,
          onReport: onReportIssue,
        );
      case RiderNav.routeAlerts:
        return _RouteAlertsView(state: appState, onNavigate: onNavigate);
      case RiderNav.report:
        return _ReportView(onSubmit: onReportIssue);
      case RiderNav.history:
        return _HistoryView(state: appState);
      case RiderNav.queue:
        return _QueueView(
          state: appState,
          tracking: tracking,
          online: online,
          onSync: onRetrySync,
        );
    }
  }
}

class _DashboardHome extends StatelessWidget {
  final MockAppState state;
  final ValueChanged<RiderNav> onNavigate;
  final VoidCallback onStartTrip;
  final VoidCallback onAddProof;
  final VoidCallback onReportIssue;
  final VoidCallback onToggleOffline;
  final ValueChanged<String> onDownloadMap;
  final ValueChanged<String> onRefreshMap;
  final RiderTrackingState tracking;
  final RiderContext? riderContext;
  final bool online;
  final VoidCallback onToggleSharing;
  final VoidCallback onCheckIn;
  final VoidCallback onRetrySync;
  final VoidCallback onDismissTrackingError;

  const _DashboardHome({
    required this.state,
    required this.onNavigate,
    required this.onStartTrip,
    required this.onAddProof,
    required this.onReportIssue,
    required this.onToggleOffline,
    required this.onDownloadMap,
    required this.onRefreshMap,
    required this.tracking,
    required this.riderContext,
    required this.online,
    required this.onToggleSharing,
    required this.onCheckIn,
    required this.onRetrySync,
    required this.onDismissTrackingError,
  });

  @override
  Widget build(BuildContext context) {
    final assignment = state.activeRiderAssignment;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Good morning, ${(riderContext?.fullName ?? (DemoMode.enabled ? state.activeRider.name : 'Rider')).split(' ').last}',
              style: AppTextStyles.pageHeading),
          const SizedBox(height: 4),
          Text('Your next action is ready below.', style: AppTextStyles.bodySmall),
          const SizedBox(height: 16),
          if (assignment == null) ...[
            SectionTitle(title: 'Active delivery'),
            const CardSurface(
              padding: EdgeInsets.all(16),
              child: Text('No active delivery. Assigned deliveries will show here.'),
            ),
          ] else ...[
            SectionTitle(
              title: 'Active delivery',
              action: TextButton(
                  onPressed: () => onNavigate(RiderNav.trip),
                  child: const Text('Open trip')),
            ),
            CardSurface(
              padding: const EdgeInsets.all(16),
              borderColor: assignment.risk == RiskLevel.critical
                  ? AppColors.signalRed700.withOpacity(0.5)
                  : AppColors.hairline,
              leftAccentColor: assignment.risk == RiskLevel.critical
                  ? AppColors.signalRed700
                  : AppColors.saffron600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${assignment.tripId} · ${assignment.cargo}',
                            style: AppTextStyles.cardTitle),
                      ),
                      RiskBadge(level: assignment.risk),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _RoutePair(from: assignment.origin, to: assignment.destination),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Metric(label: 'ETA', value: assignment.eta),
                      _Metric(label: 'Remaining', value: assignment.distanceRemaining),
                      _Metric(label: 'Window', value: assignment.window),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: assignment.progress / 100,
                      minHeight: 8,
                      backgroundColor: AppColors.navyTint,
                      valueColor: const AlwaysStoppedAnimation(AppColors.deepGreen700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${assignment.progress}% complete · Recipient: ${assignment.recipient}',
                      style: AppTextStyles.caption),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: onStartTrip,
                      icon: Icon(assignment.status == RiderTripStatus.enRoute
                          ? Icons.navigation_outlined
                          : Icons.play_arrow_outlined),
                      label: Text(assignment.status == RiderTripStatus.enRoute
                          ? 'Continue trip'
                          : 'Start trip'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SectionTitle(
            title: 'Live location sharing',
            action: TextButton(
                onPressed: () => onNavigate(RiderNav.queue),
                child: const Text('Sync queue')),
          ),
          LiveSharingCard(
            tracking: tracking,
            riderContext: riderContext,
            online: online,
            onToggle: onToggleSharing,
            onCheckIn: onCheckIn,
            onRetry: onRetrySync,
            onDismissError: onDismissTrackingError,
          ),
          SectionTitle(title: 'Safety and route status'),
          RiderRouteStatusCard(onReview: () => onNavigate(RiderNav.trip)),
          SectionTitle(title: 'Road disruption risk · your routes'),
          const MlAssignedRoutesCard(),
          SectionTitle(title: 'Offline maps'),
          _OfflineMapsCard(
            regions: state.offlineMapRegions,
            onDownload: onDownloadMap,
            onRefresh: onRefreshMap,
          ),
          SectionTitle(title: 'Quick actions'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _ActionTile(icon: Icons.sos_outlined, label: 'SOS / emergency', tone: ChipTone.critical,
                  onTap: onReportIssue),
              _ActionTile(icon: Icons.report_problem_outlined, label: 'Report issue', tone: ChipTone.saffron,
                  onTap: onReportIssue),
              _ActionTile(icon: Icons.photo_camera_outlined, label: 'Add delivery proof', tone: ChipTone.navy,
                  onTap: onAddProof),
              _ActionTile(icon: Icons.location_on_outlined, label: 'Send check-in', tone: ChipTone.clear,
                  onTap: onCheckIn),
            ],
          ),
          SectionTitle(title: 'Offline and sync'),
          CardSurface(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon((state.isOffline || !online) ? Icons.wifi_off_outlined : Icons.wifi_outlined,
                    color: (state.isOffline || !online) ? AppColors.saffronDark : AppColors.deepGreen700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (state.isOffline || !online)
                        ? '${state.riderQueueCount + tracking.queued} actions queued · will sync when online'
                        : tracking.queued > 0
                            ? 'Online · ${tracking.queued} position${tracking.queued == 1 ? '' : 's'} syncing'
                            : 'Online · everything synced',
                    style: AppTextStyles.bodySmallMedium,
                  ),
                ),
                TextButton(onPressed: onToggleOffline,
                    child: Text(state.isOffline ? 'Reconnect' : 'Demo offline')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineMapsCard extends StatelessWidget {
  final List<OfflineMapRegion> regions;
  final ValueChanged<String> onDownload;
  final ValueChanged<String> onRefresh;

  const _OfflineMapsCard({
    required this.regions,
    required this.onDownload,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, color: AppColors.navy900),
              const SizedBox(width: 10),
              Expanded(
                child: Text('MAPOG offline coverage',
                    style: AppTextStyles.bodySmallMedium),
              ),
              const StatusChip(
                tone: ChipTone.clear,
                label: 'Ready offline',
                icon: Icons.download_done_outlined,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Download route tiles before leaving coverage. Navigation overlays remain available without data.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 10),
          for (final region in regions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(region.name, style: AppTextStyles.captionSemibold),
                        Text('${region.coverage} · ${region.size}',
                            style: AppTextStyles.disclaimer),
                        if (region.status == OfflineMapRegionStatus.downloading)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: LinearProgressIndicator(
                                value: region.downloadProgress / 100),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: region.status == OfflineMapRegionStatus.available
                        ? () => onRefresh(region.id)
                        : () => onDownload(region.id),
                    child: Text(region.status == OfflineMapRegionStatus.available
                        ? 'Refresh'
                        : region.status == OfflineMapRegionStatus.downloading
                            ? 'Downloading'
                            : 'Download'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveriesView extends StatelessWidget {
  final MockAppState state;
  final VoidCallback onAccept;
  final ValueChanged<RiderNav> onNavigate;

  const _DeliveriesView({required this.state, required this.onAccept, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('Assigned deliveries', style: AppTextStyles.pageHeading),
        const SizedBox(height: 4),
        Text('${state.riderAssignments.length} tasks · today', style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        for (final item in state.riderAssignments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardSurface(
              padding: const EdgeInsets.all(14),
              onTap: item.status == RiderTripStatus.enRoute
                  ? () => onNavigate(RiderNav.trip)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('${item.id} · ${item.cargo}', style: AppTextStyles.cardTitle)),
                    RiskBadge(level: item.risk, compact: true),
                  ]),
                  const SizedBox(height: 10),
                  _RoutePair(from: item.origin, to: item.destination),
                  const SizedBox(height: 8),
                  Text('${item.window} · ${item.recipient}', style: AppTextStyles.caption),
                  if (item.decision == AssignmentDecision.pending) ...[
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: OutlinedButton(
                        onPressed: onAccept, child: const Text('Accept assignment'))),
                  ] else
                    Padding(padding: const EdgeInsets.only(top: 10),
                        child: StatusChip(
                            tone: item.status == RiderTripStatus.enRoute
                                ? ChipTone.clear : ChipTone.navy,
                            label: _statusLabel(item.status),
                            icon: Icons.info_outline)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActiveTripView extends StatelessWidget {
  final MockAppState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onProof;
  final VoidCallback onReport;

  const _ActiveTripView({required this.state, required this.onPause, required this.onResume,
      required this.onComplete, required this.onProof, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final item = state.activeRiderAssignment;
    if (item == null) {
      return const DemoEmptyState(
          title: 'No active trip', icon: Icons.route_outlined);
    }
    final paused = item.status == RiderTripStatus.paused;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CardSurface(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(item.tripId, style: AppTextStyles.pageHeading)), RiskBadge(level: item.risk)]),
            const SizedBox(height: 14),
            RiderLogisticsPanel(isOffline: state.isOffline),
            const SizedBox(height: 16),
            Text('Road disruption risk ahead', style: AppTextStyles.bodySmallMedium),
            const SizedBox(height: 8),
            const MlTripAdvisory(),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 46,
                child: ElevatedButton.icon(
                  onPressed: paused ? onResume : onPause,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  label: Text(paused ? 'Resume trip' : 'Pause trip'),
                )),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: onReport, icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Report issue')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: onProof, icon: const Icon(Icons.photo_camera_outlined),
                label: Text(item.proofSubmitted ? 'Proof queued' : 'Add delivery proof')),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: item.proofSubmitted ? onComplete : null,
              icon: const Icon(Icons.flag_outlined),
              label: Text(item.proofSubmitted
                ? 'Mark arrival'
                : 'Add proof before marking arrival')),
          ]),
        ),
      ],
    );
  }
}

class _RouteAlertsView extends StatelessWidget {
  final MockAppState state;
  final ValueChanged<RiderNav> onNavigate;
  const _RouteAlertsView({required this.state, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Route safety', style: AppTextStyles.pageHeading),
      const SizedBox(height: 14),
      Text('Model risk on this trip', style: AppTextStyles.bodySmallMedium),
      const SizedBox(height: 8),
      const MlTripAdvisory(),
      const SizedBox(height: 18),
      Text('Mapped and reported hazards', style: AppTextStyles.bodySmallMedium),
      const SizedBox(height: 8),
      const RiderRouteHazards(),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: () => onNavigate(RiderNav.trip),
          icon: const Icon(Icons.navigation_outlined), label: const Text('Return to active trip')),
    ]);
  }
}

class _ReportView extends StatelessWidget {
  final VoidCallback onSubmit;
  const _ReportView({required this.onSubmit});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Report an issue', style: AppTextStyles.pageHeading),
        const SizedBox(height: 6),
        Text('Reports are saved locally first when connectivity is unavailable.', style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        for (final row in const [
          ('Road or weather hazard', Icons.terrain_outlined),
          ('Vehicle breakdown or unsafe condition', Icons.car_repair_outlined),
          ('Delivery or recipient issue', Icons.inventory_2_outlined),
          ('Emergency assistance', Icons.sos_outlined),
        ])
          Padding(padding: const EdgeInsets.only(bottom: 10), child: CardSurface(
              padding: const EdgeInsets.all(14), onTap: onSubmit,
              child: Row(children: [Icon(row.$2, color: AppColors.navy900), const SizedBox(width: 12),
                  Expanded(child: Text(row.$1, style: AppTextStyles.bodySmallMedium)),
                  const Icon(Icons.chevron_right)]))),
      ]);
}

class _HistoryView extends StatelessWidget {
  final MockAppState state;
  const _HistoryView({required this.state});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Delivery history', style: AppTextStyles.pageHeading),
        const SizedBox(height: 14),
        CardSurface(padding: const EdgeInsets.all(14), child: Row(children: [
          const Icon(Icons.check_circle_outline, color: AppColors.deepGreen700), const SizedBox(width: 12),
          Expanded(child: Text('6 deliveries completed this month', style: AppTextStyles.bodySmallMedium)),
          Text('100%', style: AppTextStyles.cardTitle),
        ])),
        const SizedBox(height: 12),
        const CardSurface(padding: EdgeInsets.all(14), child: Text('No failed or disputed deliveries in the current demo period.')),
      ]);
}

class _QueueView extends StatelessWidget {
  final MockAppState state;
  final RiderTrackingState tracking;
  final bool online;
  final VoidCallback onSync;
  const _QueueView({required this.state, required this.tracking, required this.online, required this.onSync});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Offline queue', style: AppTextStyles.pageHeading),
        const SizedBox(height: 6),
        Text(
            '${state.riderQueueCount + tracking.queued} actions waiting to sync · '
            '${online ? 'online' : 'offline'}'
            '${tracking.lastSyncAt == null ? '' : ' · last position sync ${_hhmm(tracking.lastSyncAt!)}'}',
            style: AppTextStyles.bodySmall),
        const SizedBox(height: 14),
        for (final row in [
          ('Delivery proofs', state.queuedProofs.length, Icons.photo_camera_outlined),
          ('Issue reports', state.queuedIssues.length, Icons.report_problem_outlined),
          ('Location pings', tracking.queued, Icons.location_on_outlined),
        ])
          Padding(padding: const EdgeInsets.only(bottom: 10), child: CardSurface(padding: const EdgeInsets.all(14), child: Row(children: [
            Icon(row.$3, color: AppColors.navy900), const SizedBox(width: 12), Expanded(child: Text(row.$1)), Text('${row.$2}', style: AppTextStyles.cardTitle),
          ]))),
        ElevatedButton.icon(
            onPressed: tracking.uploading ? null : onSync,
            icon: const Icon(Icons.sync),
            label: Text(tracking.uploading ? 'Syncing…' : 'Retry sync')),
        if (tracking.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tracking.error!, style: AppTextStyles.caption.copyWith(color: AppColors.saffronDark)),
          ),
      ]);

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _RoutePair extends StatelessWidget {
  final String from;
  final String to;
  const _RoutePair({required this.from, required this.to});
  @override
  Widget build(BuildContext context) => Row(children: [
        Column(children: [const Icon(Icons.radio_button_checked, size: 14, color: AppColors.navy900), Container(width: 1, height: 20, color: AppColors.hairline), const Icon(Icons.location_on, size: 16, color: AppColors.signalRed700)]),
        const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(from, style: AppTextStyles.bodySmall), const SizedBox(height: 8), Text(to, style: AppTextStyles.bodySmallMedium)])),
      ]);
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: AppTextStyles.caption), const SizedBox(height: 3), Text(value, style: AppTextStyles.cardTitle, overflow: TextOverflow.ellipsis)]));
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final ChipTone tone;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.tone, required this.onTap});
  @override
  Widget build(BuildContext context) => CardSurface(onTap: onTap, padding: const EdgeInsets.all(12), child: Row(children: [Icon(icon, color: _toneColor(tone), size: 21), const SizedBox(width: 8), Expanded(child: Text(label, style: AppTextStyles.captionSemibold))]));
}

Color _toneColor(ChipTone tone) => switch (tone) {
      ChipTone.critical => AppColors.signalRed700,
      ChipTone.saffron => AppColors.saffron600,
      ChipTone.clear => AppColors.deepGreen700,
      _ => AppColors.navy900,
    };

String _statusLabel(RiderTripStatus status) => switch (status) {
      RiderTripStatus.assigned => 'Assigned',
      RiderTripStatus.accepted => 'Accepted',
      RiderTripStatus.enRoute => 'En route',
      RiderTripStatus.paused => 'Paused',
      RiderTripStatus.rerouting => 'Rerouting',
      RiderTripStatus.arrived => 'Arrived',
      RiderTripStatus.completed => 'Completed',
      RiderTripStatus.failed => 'Failed',
      RiderTripStatus.cancelled => 'Cancelled',
    };