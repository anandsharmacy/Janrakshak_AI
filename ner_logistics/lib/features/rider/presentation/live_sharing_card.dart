import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';
import '../application/location_policy.dart';
import '../application/rider_tracking_controller.dart';
import '../domain/rider_context.dart';

/// Rider dashboard card: live location sharing status + controls.
///
/// Everything shown here comes from [RiderTrackingState] (device side) and
/// [RiderContext] (Supabase side), so the rider can always tell whether the
/// control room is seeing them, and what is still queued.
class LiveSharingCard extends StatelessWidget {
  final RiderTrackingState tracking;
  final RiderContext? riderContext;
  final bool online;
  final VoidCallback onToggle;
  final VoidCallback onCheckIn;
  final VoidCallback onRetry;
  final VoidCallback onDismissError;

  const LiveSharingCard({
    super.key,
    required this.tracking,
    required this.riderContext,
    required this.online,
    required this.onToggle,
    required this.onCheckIn,
    required this.onRetry,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    final sharing = tracking.isSharing;
    final (icon, color, title) = switch (tracking.status) {
      TrackingStatus.tracking => (Icons.sensors, AppColors.deepGreen700, 'Sharing live'),
      TrackingStatus.paused => (Icons.pause_circle_outline, AppColors.saffron600, 'Sharing · low power'),
      TrackingStatus.starting => (Icons.gps_not_fixed, AppColors.navy900, 'Starting GPS…'),
      TrackingStatus.error => (Icons.gps_off, AppColors.signalRed700, 'Cannot share location'),
      TrackingStatus.off => (Icons.location_off_outlined, AppColors.slate500, 'Not sharing'),
    };
    final shipment = riderContext?.activeShipment;
    final last = tracking.lastFix;

    return CardSurface(
      padding: const EdgeInsets.all(14),
      leftAccentColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.cardTitle),
                    Text(
                      shipment == null
                          ? 'No shipment assigned · position still visible to officers'
                          : 'Attached to ${shipment.shipmentNumber}'
                              '${shipment.destination == null ? '' : ' → ${shipment.destination}'}',
                      style: AppTextStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                tone: online ? ChipTone.clear : ChipTone.saffron,
                icon: online ? Icons.wifi_outlined : Icons.wifi_off_outlined,
                label: online ? 'Online' : 'Offline',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                label: 'Last fix',
                value: last == null ? '—' : _ago(last.recordedAt),
                hint: last?.accuracyM == null ? null : '±${last!.accuracyM!.round()} m',
              ),
              _Metric(
                label: 'Speed',
                value: last?.speedKmph == null ? '—' : '${last!.speedKmph!.round()} km/h',
                hint: tracking.lastDecision?.label,
              ),
              _Metric(
                label: 'Queued',
                value: '${tracking.queued}',
                hint: tracking.uploading
                    ? 'Uploading…'
                    : tracking.lastSyncAt == null
                        ? 'Never synced'
                        : 'Synced ${_ago(tracking.lastSyncAt!)}',
              ),
            ],
          ),
          if (tracking.permission == LocationPermissionState.whileInUse && sharing) ...[
            const SizedBox(height: 8),
            Text(
              'Background sharing uses the “sharing location” notification. Allow “All the time” in system settings for the most reliable tracking.',
              style: AppTextStyles.caption,
            ),
          ],
          if (tracking.error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              decoration: BoxDecoration(
                color: AppColors.saffronBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.saffron600.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined, size: 16, color: AppColors.saffronDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tracking.error!,
                        style: AppTextStyles.caption.copyWith(color: AppColors.saffronDark)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AppColors.saffronDark),
                    onPressed: onDismissError,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: tracking.status == TrackingStatus.starting ? null : onToggle,
                    icon: Icon(sharing ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 18),
                    label: Text(sharing ? 'Stop sharing' : 'Start sharing'),
                    style: sharing
                        ? ElevatedButton.styleFrom(backgroundColor: AppColors.signalRed700)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: onCheckIn,
                  icon: const Icon(Icons.my_location_outlined, size: 18),
                  label: const Text('Check-in'),
                ),
              ),
            ],
          ),
          if (tracking.queued > 0 && !tracking.uploading) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.sync, size: 16),
                label: Text('Sync ${tracking.queued} queued position${tracking.queued == 1 ? '' : 's'} now'),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Sends a fix every ~10 s while moving and a heartbeat every 60 s. '
            'Positions queue offline and sync automatically when back online.',
            style: AppTextStyles.caption.copyWith(color: AppColors.slate500.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return DateFormat('d MMM HH:mm').format(t.toLocal());
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  const _Metric({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 3),
            Text(value, style: AppTextStyles.cardTitle, overflow: TextOverflow.ellipsis),
            if (hint != null)
              Text(hint!,
                  style: AppTextStyles.caption.copyWith(fontSize: 10),
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}
