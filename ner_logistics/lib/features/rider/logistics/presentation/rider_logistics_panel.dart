import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../mock_data/models.dart';
import '../../../../services/routing/trip_plan.dart';
import '../../../../shared/map/ner_map.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/text_styles.dart';
import '../application/rider_logistics_service.dart';
import '../domain/rider.dart';

/// Active-trip panel for the signed-in rider: live map, current route card,
/// route-safety warning with explicit diversion confirmation, and the riders
/// nearby. Reads everything from [riderLogisticsProvider]; holds no rider data.
class RiderLogisticsPanel extends ConsumerWidget {
  final bool isOffline;

  const RiderLogisticsPanel({super.key, required this.isOffline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(riderLogisticsProvider);
    final service = ref.read(riderLogisticsProvider.notifier);
    final rider = s.rider;

    if (s.loading) {
      return const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator(color: AppColors.navy900)),
      );
    }
    if (rider == null) {
      return AlertBanner(
        tone: BannerTone.caution,
        title: 'Rider profile unavailable',
        text: s.error ?? 'Sign in with a rider account to load your route.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdentityRow(rider: rider, stage: s.stage),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 220,
            child: _RiderMap(state: s, isOffline: isOffline),
          ),
        ),
        const SizedBox(height: 12),
        if (s.warningActive) ...[
          if (s.warningDismissed)
            _CompactWarning(incident: s.incident!, onReview: service.reviewWarning)
          else
            _SafetyWarning(
              state: s,
              onConfirm: service.confirmDiversion,
              onDismiss: service.dismissWarning,
            ),
          const SizedBox(height: 12),
        ],
        if (s.diverted && s.stage != RiderFlowStage.arrived) ...[
          AlertBanner(
            tone: BannerTone.clear,
            title: 'Following the alternate route',
            text: 'Diversion via Umroi confirmed. ${s.incident?.location ?? 'The blocked stretch'} is avoided.',
          ),
          const SizedBox(height: 12),
        ],
        if (s.stage == RiderFlowStage.arrived) ...[
          AlertBanner(
            tone: BannerTone.clear,
            title: 'Arrived at ${rider.destination ?? 'destination'}',
            text: 'Route ${rider.routeId ?? ''} complete. Add delivery proof to close the trip.',
          ),
          const SizedBox(height: 12),
        ],
        _CurrentRouteCard(rider: rider, state: s),
        SectionTitle(title: 'Nearby riders · within ${(kNearbyRadiusM / 1000).round()} km'),
        _NearbyRiders(
          riders: s.nearby,
          selectedId: s.selectedNearbyId,
          onSelect: service.selectNearby,
        ),
      ],
    );
  }
}

/// Dashboard-home summary of the route status and any live warning. Replaces
/// the previous static copy in the "Safety and route status" card.
class RiderRouteStatusCard extends ConsumerWidget {
  final VoidCallback onReview;
  const RiderRouteStatusCard({super.key, required this.onReview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(riderLogisticsProvider);
    final rider = s.rider;
    final incident = s.incident;
    final warning = s.warningActive && incident != null;
    final status = rider?.routeStatus ?? RiderRouteStatus.open;
    return CardSurface(
      padding: const EdgeInsets.all(14),
      leftAccentColor: warning ? AppColors.saffron600 : null,
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                warning ? Icons.warning_amber_outlined : Icons.check_circle_outline,
                color: warning ? AppColors.saffron600 : AppColors.deepGreen700,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  warning
                      ? '${incident.title} · ${incident.location}'
                      : rider?.routeId == null
                          ? 'No route assigned'
                          : 'Route ${rider!.routeId} · no hazards reported ahead',
                  style: AppTextStyles.bodySmallMedium,
                ),
              ),
              TextButton(onPressed: onReview, child: const Text('Review')),
            ],
          ),
          const Divider(),
          Row(
            children: [
              const Icon(Icons.alt_route_outlined, color: AppColors.navy900),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rider == null
                      ? 'Rider profile loading'
                      : '${rider.origin ?? '—'} → ${rider.destination ?? '—'} · ${rider.speedLabel}',
                  style: AppTextStyles.bodySmall,
                ),
              ),
              _RouteStatusChip(status: status),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _IdentityRow extends StatelessWidget {
  final Rider rider;
  final RiderFlowStage stage;
  const _IdentityRow({required this.rider, required this.stage});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rider.name, style: AppTextStyles.cardTitle),
              const SizedBox(height: 2),
              Text(
                '${rider.callsign} · ${rider.id} · ${rider.vehicleType} · ${rider.district}',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const DemoTag(),
            const SizedBox(height: 6),
            StatusChip(tone: _stageTone(stage), label: stage.label, icon: _stageIcon(stage)),
          ],
        ),
      ],
    );
  }
}

class _RiderMap extends StatelessWidget {
  final RiderLogisticsState state;
  final bool isOffline;
  const _RiderMap({required this.state, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    final rider = state.rider!;
    final route = state.route;
    final incident = state.incident;
    final aheadTone = switch (rider.routeStatus) {
      RiderRouteStatus.open || RiderRouteStatus.diverted => MapLineTone.clear,
      RiderRouteStatus.atRisk => MapLineTone.caution,
      RiderRouteStatus.blocked => MapLineTone.critical,
    };
    final destination = route?.end ?? rider.point;

    return NerMap(
      interactive: false,
      offlineMode: isOffline,
      showRouteLabels: false,
      fitPoints: [rider.point, destination, ...state.offeredAlternate],
      fitPadding: const EdgeInsets.all(24),
      // Reframe only when the driven road changes, never on every tick.
      fitKey: state.diverted ? 'diverted' : 'original',
      routes: [
        if (state.avoidedPath.length >= 2)
          MapRoute(points: state.avoidedPath, tone: MapLineTone.avoided),
        if (state.travelled.length >= 2)
          MapRoute(points: state.travelled, tone: MapLineTone.travelled),
        if (state.ahead.length >= 2) MapRoute(points: state.ahead, tone: aheadTone),
        if (state.offeredAlternate.length >= 2)
          MapRoute(points: state.offeredAlternate, tone: MapLineTone.candidate),
      ],
      incidents: [
        if (incident != null && state.incidentDetected)
          MapIncident(
            id: incident.id,
            point: incident.point,
            severity: Priority.critical,
            type: IncidentType.landslide,
            label: '${incident.title} · ${incident.location}',
          ),
      ],
      pois: [
        MapPoi(point: destination, kind: MapPoiKind.destination, label: rider.destination ?? 'Destination'),
      ],
      vehicles: [
        // Nearby riders first so the primary marker draws on top. Smaller,
        // no glow; the tap tooltip is the minimal popup (no phone number).
        for (final r in state.nearby)
          MapVehicle(
            id: r.id,
            point: r.point,
            risk: Priority.low,
            label: '${r.name} · ${r.callsign} · ${r.vehicleType} · ${r.district} · ${r.status.label}',
          ),
        MapVehicle(
          id: rider.id,
          point: rider.point,
          risk: Priority.low,
          label: '${rider.callsign} · you are here · ${rider.speedLabel}',
          self: true,
        ),
      ],
    );
  }
}

class _CurrentRouteCard extends StatelessWidget {
  final Rider rider;
  final RiderLogisticsState state;
  const _CurrentRouteCard({required this.rider, required this.state});

  @override
  Widget build(BuildContext context) {
    final eta = rider.eta;
    return CardSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('CURRENT ROUTE', style: AppTextStyles.eyebrow)),
              _RouteStatusChip(status: rider.routeStatus),
            ],
          ),
          const SizedBox(height: 10),
          _KV('Origin', rider.origin ?? '—'),
          _KV('Destination', rider.destination ?? '—'),
          _KV('Route', rider.routeId ?? '—'),
          _KV('Speed', state.halted ? 'Stopped · road blocked ahead' : '${rider.speedLabel} (live)'),
          _KV('ETA', eta == null ? '—' : '${etaClock(eta)} · ${formatDuration(eta)}'),
          _KV('Remaining', formatDistance(state.remainingM)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rider.routeProgress,
              minHeight: 8,
              backgroundColor: AppColors.navyTint,
              valueColor: const AlwaysStoppedAnimation(AppColors.deepGreen700),
            ),
          ),
          const SizedBox(height: 6),
          Text('${(rider.routeProgress * 100).round()}% of route complete', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _SafetyWarning extends StatelessWidget {
  final RiderLogisticsState state;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  const _SafetyWarning({required this.state, required this.onConfirm, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final incident = state.incident!;
    final blocked = state.halted;
    final alternateReady = state.canConfirmDiversion;
    final aheadM = state.incidentAheadM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AlertBanner(
          tone: blocked ? BannerTone.critical : BannerTone.caution,
          title: blocked ? 'Road blocked ahead — stopped' : 'Route safety warning',
          text: blocked
              ? '${incident.title} near ${incident.location}. Confirm the diversion to continue.'
              : 'Incident reported ahead on your route near ${incident.location}: '
                  '${incident.title}, ${formatDistance(aheadM)} ahead.',
        ),
        const SizedBox(height: 8),
        if (alternateReady) ...[
          Text(
            'Alternate route calculated via Umroi. Your ETA and route status update once you confirm.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.alt_route_outlined),
              label: const Text('Confirm diversion'),
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('Not now — keep current route')),
        ] else
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy900),
              ),
              const SizedBox(width: 8),
              Text('Calculating alternate route…', style: AppTextStyles.caption),
            ],
          ),
      ],
    );
  }
}

class _CompactWarning extends StatelessWidget {
  final RouteIncident incident;
  final VoidCallback onReview;
  const _CompactWarning({required this.incident, required this.onReview});

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leftAccentColor: AppColors.saffron600,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: AppColors.saffron600, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${incident.title} · ${incident.location} · route AT RISK',
                style: AppTextStyles.bodySmallMedium),
          ),
          TextButton(onPressed: onReview, child: const Text('Review')),
        ],
      ),
    );
  }
}

class _NearbyRiders extends StatelessWidget {
  final List<Rider> riders;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  const _NearbyRiders({required this.riders, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (riders.isEmpty) {
      return CardSurface(
        padding: const EdgeInsets.all(14),
        child: Text('No active riders within ${(kNearbyRadiusM / 1000).round()} km of your position.',
            style: AppTextStyles.bodySmall),
      );
    }
    return Column(
      children: [
        for (final r in riders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardSurface(
              padding: const EdgeInsets.all(12),
              onTap: () => onSelect(r.id),
              borderColor: r.id == selectedId ? AppColors.gold : null,
              child: Row(
                children: [
                  const Icon(Icons.two_wheeler_outlined, color: AppColors.slate500, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.name} · ${r.callsign}', style: AppTextStyles.bodySmallMedium),
                        Text('${r.vehicleType} · ${r.district}', style: AppTextStyles.caption),
                        if (r.id == selectedId)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${r.origin ?? '—'} → ${r.destination ?? '—'} · ${r.speedLabel}',
                              style: AppTextStyles.caption,
                            ),
                          ),
                      ],
                    ),
                  ),
                  StatusChip(
                    tone: r.isActive ? ChipTone.clear : ChipTone.muted,
                    label: r.status.label,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RouteStatusChip extends StatelessWidget {
  final RiderRouteStatus status;
  const _RouteStatusChip({required this.status});

  @override
  Widget build(BuildContext context) => StatusChip(
        tone: switch (status) {
          RiderRouteStatus.open => ChipTone.clear,
          RiderRouteStatus.atRisk => ChipTone.saffron,
          RiderRouteStatus.blocked => ChipTone.critical,
          RiderRouteStatus.diverted => ChipTone.navy,
        },
        label: status.label,
        icon: switch (status) {
          RiderRouteStatus.open => Icons.check,
          RiderRouteStatus.atRisk => Icons.warning_amber_outlined,
          RiderRouteStatus.blocked => Icons.block,
          RiderRouteStatus.diverted => Icons.alt_route_outlined,
        },
      );
}

class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV(this.k, this.v);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 92, child: Text(k, style: AppTextStyles.caption)),
            Expanded(child: Text(v, style: AppTextStyles.bodySmallMedium)),
          ],
        ),
      );
}

ChipTone _stageTone(RiderFlowStage stage) => switch (stage) {
      RiderFlowStage.incidentDetected || RiderFlowStage.safetyWarning => ChipTone.critical,
      RiderFlowStage.alternateReady => ChipTone.saffron,
      RiderFlowStage.diversionConfirmed ||
      RiderFlowStage.routeSwitched ||
      RiderFlowStage.arrived =>
        ChipTone.clear,
      _ => ChipTone.navy,
    };

IconData _stageIcon(RiderFlowStage stage) => switch (stage) {
      RiderFlowStage.home => Icons.home_outlined,
      RiderFlowStage.currentLocation => Icons.my_location_outlined,
      RiderFlowStage.nearbyRiders => Icons.groups_outlined,
      RiderFlowStage.incidentDetected => Icons.warning_outlined,
      RiderFlowStage.safetyWarning => Icons.warning_amber_outlined,
      RiderFlowStage.alternateReady => Icons.alt_route_outlined,
      RiderFlowStage.diversionConfirmed => Icons.check,
      RiderFlowStage.routeSwitched => Icons.swap_calls_outlined,
      RiderFlowStage.continuing => Icons.navigation_outlined,
      RiderFlowStage.arrived => Icons.flag_outlined,
    };
