import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../mock_data/models.dart';
import '../../../shared/map/ner_geo.dart';
import '../../../shared/map/ner_map.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';
import '../application/live_riders_controller.dart';
import '../domain/live_rider.dart';

/// Map markers for every live rider. Shared by the dedicated Live Riders
/// screen and by the district / regional situation maps' Logistics layer.
List<MapVehicle> liveRiderVehicles(
  LiveRidersState? state, {
  void Function(String userId)? onTap,
}) {
  if (state == null) return const [];
  return [
    for (final r in state.sorted)
      MapVehicle(
        id: 'rider-${r.userId}',
        point: r.point,
        risk: r.riskPriority,
        live: true,
        heading: r.isMoving ? r.headingDeg : null,
        stale: r.isStaleAt(state.now, window: state.staleWindow),
        selected: state.selectedId == r.userId,
        onTap: onTap == null ? null : () => onTap(r.userId),
        label: '${r.fullName} · ${r.vehicleLabel}'
            '${r.shipmentNumber == null ? '' : ' · ${r.shipmentNumber}'}'
            ' · ${LiveRider.ageLabel(r.age(state.now))}',
      ),
  ];
}

/// "Live Riders" — the shared officer view of every rider reporting from the
/// mobile app. Used by the Field, District and Control Room shells.
///
/// [embedded] = true when the parent already scrolls (district / control
/// shells wrap their body in a SingleChildScrollView); otherwise the screen
/// provides its own scroll view.
class LiveRidersScreen extends ConsumerWidget {
  final bool embedded;
  const LiveRidersScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveRidersProvider);
    final controller = ref.read(liveRidersProvider.notifier);

    final body = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator(color: AppColors.navy900)),
      ),
      error: (e, _) => _ErrorState(
        message: e.toString(),
        onRetry: () => ref.invalidate(liveRidersProvider),
      ),
      data: (state) => _LiveRidersBody(state: state, controller: controller),
    );

    if (embedded) return body;
    return RefreshIndicator(
      color: AppColors.navy900,
      onRefresh: controller.refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: body,
      ),
    );
  }
}

class _LiveRidersBody extends StatelessWidget {
  final LiveRidersState state;
  final LiveRidersController controller;
  const _LiveRidersBody({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final riders = state.sorted;
    final selected = state.selected;
    final fitPoints = selected != null
        ? [selected.point, ...state.trail]
        : riders.isEmpty
            ? const [NerGeo.guwahati]
            : [for (final r in riders) r.point];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FeedHeader(state: state, onRefresh: controller.refresh),
        if (state.error != null) ...[
          const SizedBox(height: 8),
          AlertBanner(
            tone: BannerTone.caution,
            title: 'Live feed problem',
            text: state.error!,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: KpiTile(label: 'On duty', value: '${state.activeCount}', tone: KpiTone.clear)),
            const SizedBox(width: 10),
            Expanded(child: KpiTile(label: 'Moving', value: '${state.movingCount}', tone: KpiTone.navy)),
            const SizedBox(width: 10),
            Expanded(child: KpiTile(label: 'Stale', value: '${state.staleCount}', tone: state.staleCount > 0 ? KpiTone.saffron : KpiTone.navy)),
            const SizedBox(width: 10),
            Expanded(child: KpiTile(label: 'Riders', value: '${state.total}', tone: KpiTone.navy)),
          ],
        ),
        const SizedBox(height: 14),
        CardSurface(
          child: SizedBox(
            height: 320,
            child: Stack(
              children: [
                Positioned.fill(
                  child: NerMap(
                    interactive: true,
                    showControls: true,
                    showRouteLabels: false,
                    maxFitZoom: selected != null ? 14 : 11,
                    fitPoints: fitPoints,
                    fitPadding: const EdgeInsets.all(40),
                    fitKey: selected?.userId ?? 'all-${riders.length}',
                    routes: [
                      if (state.trail.length > 1)
                        MapRoute(points: state.trail, tone: MapLineTone.candidate),
                    ],
                    vehicles: liveRiderVehicles(state, onTap: controller.select),
                  ),
                ),
                if (riders.isEmpty)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _Chip(
                      icon: Icons.info_outline,
                      label: 'No riders reporting yet',
                    ),
                  ),
                if (state.trailLoading)
                  const Positioned(
                    left: 12,
                    top: 12,
                    child: _Chip(icon: Icons.timeline, label: 'Loading trail…'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const _Legend(),
        SectionTitle(
          title: selected == null ? 'Riders' : 'Riders · 1 selected',
          action: selected == null
              ? null
              : TextButton(
                  onPressed: () => controller.select(null),
                  child: const Text('Clear'),
                ),
        ),
        if (riders.isEmpty)
          const CardSurface(
            padding: EdgeInsets.all(16),
            child: Text(
              'No rider has shared a position yet. Riders appear here as soon as they start a trip in the mobile app.',
            ),
          ),
        for (final r in riders)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RiderCard(
              rider: r,
              now: state.now,
              staleWindow: state.staleWindow,
              selected: state.selectedId == r.userId,
              onTap: () => controller.select(r.userId),
            ),
          ),
      ],
    );
  }
}

class _FeedHeader extends StatelessWidget {
  final LiveRidersState state;
  final Future<void> Function() onRefresh;
  const _FeedHeader({required this.state, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final (tone, icon, label) = switch (state.feed) {
      LiveFeedStatus.live => (ChipTone.clear, Icons.sensors, 'Live'),
      LiveFeedStatus.polling => (ChipTone.saffron, Icons.sync, 'Polling every 30 s'),
      LiveFeedStatus.connecting => (ChipTone.navy, Icons.sync, 'Connecting…'),
      LiveFeedStatus.error => (ChipTone.critical, Icons.sync_problem, 'Feed error'),
    };
    final updated = state.lastRefresh == null ? '—' : DateFormat.Hms().format(state.lastRefresh!.toLocal());
    return Row(
      children: [
        StatusChip(tone: tone, icon: icon, label: label),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Updated $updated · positions from Supabase Realtime',
              style: AppTextStyles.caption, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          color: AppColors.navy900,
          tooltip: 'Refresh',
          onPressed: onRefresh,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, {Color? ring}) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: ring ?? Colors.white, width: 2),
          ),
        );
    Widget item(Widget marker, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [marker, const SizedBox(width: 5), Text(label, style: AppTextStyles.caption)],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(dot(AppColors.navy900), 'Reporting'),
        item(dot(AppColors.saffron600), 'High-risk cargo'),
        item(dot(AppColors.signalRed700), 'Critical cargo'),
        item(dot(const Color(0xFF9AA0A8)), 'Stale (>30 min)'),
        item(dot(AppColors.navy900, ring: AppColors.gold), 'Selected'),
        item(const Icon(Icons.navigation, size: 12, color: AppColors.navy900), 'Arrow = heading'),
      ],
    );
  }
}

class _RiderCard extends StatelessWidget {
  final LiveRider rider;
  final DateTime now;
  final Duration staleWindow;
  final bool selected;
  final VoidCallback onTap;

  const _RiderCard({
    required this.rider,
    required this.now,
    required this.staleWindow,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stale = rider.isStaleAt(now, window: staleWindow);
    final age = LiveRider.ageLabel(rider.age(now));
    final accent = stale
        ? const Color(0xFF9AA0A8)
        : switch (rider.riskPriority) {
            Priority.critical => AppColors.signalRed700,
            Priority.high => AppColors.saffron600,
            _ => AppColors.deepGreen700,
          };
    return CardSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      leftAccentColor: accent,
      borderColor: selected ? AppColors.gold : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: stale ? const Color(0xFF9AA0A8) : AppColors.navy900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rider.fullName, style: AppTextStyles.cardTitle, overflow: TextOverflow.ellipsis),
                    Text(
                      '${rider.vehicleLabel}${rider.officerId == null ? '' : ' · ${rider.officerId}'}',
                      style: AppTextStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                tone: stale
                    ? ChipTone.muted
                    : rider.isOnDuty
                        ? ChipTone.clear
                        : ChipTone.saffron,
                icon: stale
                    ? Icons.history_toggle_off
                    : rider.isOnDuty
                        ? Icons.sensors
                        : Icons.pause_circle_outline,
                label: stale
                    ? 'Stale'
                    : rider.isOnDuty
                        ? 'On duty'
                        : 'Off duty',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Metric(label: 'Last seen', value: age),
              _Metric(label: 'Speed', value: rider.isMoving ? rider.speedLabel : 'Stopped'),
              _Metric(
                label: 'Accuracy',
                value: rider.accuracyM == null ? '—' : '±${rider.accuracyM!.round()} m',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 14, color: AppColors.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rider.shipmentNumber == null
                      ? 'No shipment assigned'
                      : '${rider.shipmentLabel} · ${rider.cargoDescription ?? 'cargo'} · ${rider.shipmentStatusLabel}',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (rider.riskLevel != null) ...[
                const SizedBox(width: 6),
                PriorityBadge(level: rider.riskPriority),
              ],
            ],
          ),
          if (selected) ...[
            const Divider(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _KV('District', rider.district ?? '—'),
                _KV('Route', rider.routeNumber ?? '—'),
                _KV('From', rider.originName ?? '—'),
                _KV('ETA', rider.estimatedArrival == null ? '—' : DateFormat.Hm().format(rider.estimatedArrival!.toLocal())),
                _KV('Battery', rider.batteryPercent == null ? '—' : '${rider.batteryPercent}%'),
                _KV('Position', '${rider.latitude.toStringAsFixed(5)}, ${rider.longitude.toStringAsFixed(5)}'),
                _KV('Fix time', DateFormat.Hms().format(rider.recordedAt.toLocal())),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (rider.phone != null && rider.phone!.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: rider.phone!.replaceAll(' ', ''))),
                    icon: const Icon(Icons.call_outlined, size: 16),
                    label: const Text('Call rider'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/?mlat=${rider.latitude}&mlon=${rider.longitude}#map=15/${rider.latitude}/${rider.longitude}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in maps'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(value, style: AppTextStyles.bodySmallMedium, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV(this.k, this.v);

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$k: ', style: AppTextStyles.caption),
            TextSpan(text: v, style: AppTextStyles.captionSemibold),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.navy900),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.captionSemibold),
          ],
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => CardSurface(
        padding: const EdgeInsets.all(16),
        leftAccentColor: AppColors.signalRed700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Could not load riders', style: AppTextStyles.cardTitle),
            const SizedBox(height: 6),
            Text(message, style: AppTextStyles.bodySmall),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
}

/// Convenience for other screens that want a single rider's position.
extension LiveRidersStateGeo on LiveRidersState {
  LatLng? positionOf(String userId) => riders[userId]?.point;
}
