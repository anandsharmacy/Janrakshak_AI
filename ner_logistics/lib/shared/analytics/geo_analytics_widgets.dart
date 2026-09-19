import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../mock_data/models.dart';
import '../../services/geo_providers.dart';
import '../../services/gis/spatial_analytics.dart';
import '../../services/routing/closure_impact.dart';
import '../../services/routing/trip_plan.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../map/map_models.dart';
import '../widgets/widgets.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Source chip
// ═════════════════════════════════════════════════════════════════════════════

/// Says whether numbers come from GeoServer or are on-device estimates.
class AnalyticsSourceChip extends StatelessWidget {
  final AnalyticsSource source;
  final String? note;
  const AnalyticsSourceChip({super.key, required this.source, this.note});

  @override
  Widget build(BuildContext context) {
    final live = source == AnalyticsSource.geoserver;
    final chip = StatusChip(
      tone: live ? ChipTone.clear : ChipTone.saffron,
      label: live ? 'GEOSERVER · LIVE' : 'ON-DEVICE ESTIMATE',
      icon: live ? Icons.cloud_done_outlined : Icons.phone_android_outlined,
    );
    return note == null
        ? chip
        : Tooltip(message: note!, triggerMode: TooltipTriggerMode.tap, child: chip);
  }
}

Color _severityColor(Priority p) => switch (p) {
      Priority.critical => AppColors.signalRed700,
      Priority.high || Priority.medium => AppColors.saffron600,
      Priority.low => AppColors.slate500,
    };

Widget _loading(String text) => CardSurface(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy900),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
      ]),
    );

Widget _failure(String text, VoidCallback onRetry) => CardSurface(
      padding: const EdgeInsets.all(14),
      leftAccentColor: AppColors.saffron600,
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.saffronDark),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );

// ═════════════════════════════════════════════════════════════════════════════
// Regional spatial analytics panel (control room + district analytics)
// ═════════════════════════════════════════════════════════════════════════════

class SpatialAnalyticsPanel extends ConsumerWidget {
  const SpatialAnalyticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(regionalAnalyticsProvider);
    final data = async.valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Spatial analytics',
          action: IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 18, color: AppColors.navy900),
            onPressed: () => ref.invalidate(regionalAnalyticsProvider),
          ),
        ),
        if (data != null) ...[
          AnalyticsSourceChip(source: data.source, note: data.note),
          const SizedBox(height: 10),
          _HighwayExposureCard(data.highways),
          const SizedBox(height: 10),
          _ConvoyExposureCard(data.convoys),
          const SizedBox(height: 10),
          _AreaSummaryCard(data.areas),
        ] else if (async.hasError)
          _failure('Analytics unavailable: ${async.error}',
              () => ref.invalidate(regionalAnalyticsProvider))
        else
          _loading('Computing risk exposure…'),
      ],
    );
  }
}

class _HighwayExposureCard extends StatelessWidget {
  final List<HighwayExposure> rows;
  const _HighwayExposureCard(this.rows);

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Highway risk exposure', style: AppTextStyles.cardTitle),
        const SizedBox(height: 2),
        Text('Road length inside flood / landslide zones · incidents within 2 km',
            style: AppTextStyles.caption),
        const SizedBox(height: 12),
        for (final h in rows.take(6)) ...[
          Row(children: [
            SizedBox(
              width: 56,
              child: Text(h.id,
                  style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 8,
                  child: Row(children: [
                    if (h.floodKm > 0)
                      Expanded(
                          flex: (h.floodKm * 10).round().clamp(1, 100000),
                          child: const ColoredBox(color: AppColors.saffron600)),
                    if (h.landslideKm > 0)
                      Expanded(
                          flex: (h.landslideKm * 10).round().clamp(1, 100000),
                          child: const ColoredBox(color: AppColors.signalRed700)),
                    Expanded(
                        flex: ((h.totalKm - h.exposedKm) * 10).round().clamp(1, 100000),
                        child: const ColoredBox(color: Color(0xFFE6E7E2))),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Text('${h.totalKm.round()} km',
                  textAlign: TextAlign.right, style: AppTextStyles.caption),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 3, bottom: 10),
            child: Text(
              h.exposedKm == 0 && h.nearbyIncidents == 0
                  ? 'No mapped exposure'
                  : [
                      if (h.floodKm > 0) '${h.floodKm.toStringAsFixed(1)} km flood',
                      if (h.landslideKm > 0) '${h.landslideKm.toStringAsFixed(1)} km landslide',
                      if (h.nearbyIncidents > 0)
                        '${h.nearbyIncidents} incident${h.nearbyIncidents == 1 ? '' : 's'}',
                    ].join(' · '),
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ]),
    );
  }
}

class _ConvoyExposureCard extends StatelessWidget {
  final List<ConvoyExposure> rows;
  const _ConvoyExposureCard(this.rows);

  @override
  Widget build(BuildContext context) {
    final exposed = rows.where((c) => c.exposed).toList();
    return CardSurface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Convoys inside risk zones', style: AppTextStyles.cardTitle),
        const SizedBox(height: 2),
        Text('${exposed.length} of ${rows.length} tracked vehicles',
            style: AppTextStyles.caption),
        const SizedBox(height: 10),
        if (exposed.isEmpty)
          Text('No tracked vehicle is inside a mapped flood or landslide zone.',
              style: AppTextStyles.bodySmall)
        else
          for (final c in exposed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  c.zoneKind == MapZoneKind.flood
                      ? Icons.water_drop_outlined
                      : Icons.landslide_outlined,
                  size: 18,
                  color: c.zoneKind == MapZoneKind.flood
                      ? AppColors.saffron600
                      : AppColors.signalRed700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.vehicleId} · ${c.route} → ${c.destination}',
                        style: AppTextStyles.bodySmallMedium),
                    Text(
                      'In ${c.zoneName} · nearest safe zone ${c.nearestSafeZone}, '
                      '${c.safeZoneKm.toStringAsFixed(1)} km',
                      style: AppTextStyles.caption,
                    ),
                  ]),
                ),
              ]),
            ),
      ]),
    );
  }
}

class _AreaSummaryCard extends StatelessWidget {
  final List<AreaIncidentSummary> rows;
  const _AreaSummaryCard(this.rows);

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Incidents by area', style: AppTextStyles.cardTitle),
        const SizedBox(height: 10),
        for (final a in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: Text(a.state.isEmpty ? a.area : '${a.area}, ${a.state}',
                    style: AppTextStyles.bodySmallMedium),
              ),
              for (final (count, p) in [
                (a.critical, Priority.critical),
                (a.high, Priority.high),
                (a.medium, Priority.medium),
                (a.low, Priority.low),
              ])
                if (count > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text('$count ${p.name}',
                        style: AppTextStyles.caption.copyWith(
                            color: _severityColor(p), fontWeight: FontWeight.w700)),
                  ),
              const SizedBox(width: 8),
              Text('${a.open} open', style: AppTextStyles.caption),
            ]),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Closure simulation (OSRM detours for affected convoys)
// ═════════════════════════════════════════════════════════════════════════════

class ClosureImpactView extends ConsumerWidget {
  final ClosureQuery query;
  const ClosureImpactView({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(closureImpactProvider(query));
    return async.when(
      loading: () => Row(children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy900),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Routing affected convoys around the closure (OSRM)…',
              style: AppTextStyles.bodySmall),
        ),
      ]),
      error: (e, _) => Row(children: [
        Expanded(
          child: Text('Routing engine unavailable — $e', style: AppTextStyles.bodySmall),
        ),
        TextButton(
          onPressed: () => ref.invalidate(closureImpactProvider(query)),
          child: const Text('Retry'),
        ),
      ]),
      data: (impact) {
        if (impact.convoys.isEmpty) {
          return Text('No tracked convoys on ${query.routeId}.',
              style: AppTextStyles.bodySmall);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${impact.affected} of ${impact.convoys.length} convoys on ${query.routeId} affected'
            '${impact.rerouted > 0 ? ' · ${impact.rerouted} rerouted (avg +${formatDuration(impact.averageDelay)})' : ''}'
            '${impact.holding > 0 ? ' · ${impact.holding} must hold' : ''}.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final c in impact.convoys)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  switch (c.outcome) {
                    ConvoyOutcome.rerouted => Icons.alt_route,
                    ConvoyOutcome.hold => Icons.pan_tool_outlined,
                    ConvoyOutcome.unaffected => Icons.check_circle_outline,
                    ConvoyOutcome.noDestination => Icons.help_outline,
                  },
                  size: 16,
                  color: switch (c.outcome) {
                    ConvoyOutcome.rerouted => AppColors.saffron600,
                    ConvoyOutcome.hold => AppColors.signalRed700,
                    ConvoyOutcome.unaffected => AppColors.deepGreen700,
                    ConvoyOutcome.noDestination => AppColors.slate500,
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${c.trip.vehicleId} → ${c.trip.destinationLabel}: ${switch (c.outcome) {
                      ConvoyOutcome.rerouted =>
                        'detour +${c.result!.extraKm.toStringAsFixed(0)} km, '
                            '+${formatDuration(c.result!.extraTime)}'
                            '${c.result!.via == null ? '' : ' via ${c.result!.via}'}',
                      ConvoyOutcome.hold => 'no road detour — hold at safe yard',
                      ConvoyOutcome.unaffected => 'route clear of closure',
                      ConvoyOutcome.noDestination => 'destination not mapped',
                    }}',
                    style: AppTextStyles.caption,
                  ),
                ),
              ]),
            ),
        ]);
      },
    );
  }
}

/// Detour lines for a closure, for drawing on a map (empty until computed).
List<MapRoute> closureRoutes(WidgetRef ref, ClosureQuery? query) {
  if (query == null) return const [];
  final impact = ref.watch(closureImpactProvider(query)).valueOrNull;
  if (impact == null) return const [];
  return [
    MapRoute(label: 'Closed', points: impact.closure, tone: MapLineTone.critical),
    for (final c in impact.convoys)
      if (c.outcome == ConvoyOutcome.rerouted)
        MapRoute(points: c.result!.detour!.geometry, tone: MapLineTone.candidate),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// Inspect a location (long-press on a map)
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showLocationInsight(BuildContext context, LatLng point) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _LocationInsightSheet(point),
  );
}

class _LocationInsightSheet extends ConsumerWidget {
  final LatLng point;
  const _LocationInsightSheet(this.point);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(locationInsightProvider(point));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Location analysis', style: AppTextStyles.sectionHeading)),
              if (async.valueOrNull != null)
                AnalyticsSourceChip(
                    source: async.value!.source, note: async.value!.note),
            ]),
            Text(
              '${point.latitude.toStringAsFixed(4)}° N, ${point.longitude.toStringAsFixed(4)}° E',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 12),
            async.when(
              loading: () => _loading('Querying risk layers…'),
              error: (e, _) => _failure('Could not analyse this point: $e',
                  () => ref.invalidate(locationInsightProvider(point))),
              data: (i) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Zones at this point', style: AppTextStyles.cardTitle),
                const SizedBox(height: 4),
                if (i.zones.isEmpty)
                  Text('Not inside a mapped flood, landslide or safe zone.',
                      style: AppTextStyles.bodySmall)
                else
                  for (final z in i.zones)
                    Text(
                      '• ${z.name} (${z.kind.name}'
                      '${z.susceptibility == null ? '' : ', ${z.susceptibility} susceptibility'})',
                      style: AppTextStyles.bodySmall,
                    ),
                const SizedBox(height: 12),
                Text('Incidents within 25 km', style: AppTextStyles.cardTitle),
                const SizedBox(height: 4),
                if (i.incidents.isEmpty)
                  Text('None reported.', style: AppTextStyles.bodySmall)
                else
                  for (final x in i.incidents.take(5))
                    Text(
                      '• ${x.label} · ${x.km.toStringAsFixed(1)} km · ${x.severity.name}',
                      style: AppTextStyles.bodySmall.copyWith(color: _severityColor(x.severity)),
                    ),
                if (i.nearestSafeZone != null) ...[
                  const SizedBox(height: 12),
                  Text('Nearest safe zone', style: AppTextStyles.cardTitle),
                  const SizedBox(height: 4),
                  Text(
                    '${i.nearestSafeZone!.name} · ${i.nearestSafeZone!.km.toStringAsFixed(1)} km',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
