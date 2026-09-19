import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dark_map.dart';
import '../../widgets/widgets.dart';
import 'endpoint_picker.dart';
import 'offline_card.dart';
import 'routing.dart';
import 'trip_controller.dart';
import 'trip_store.dart';

class TripPlannerScreen extends ConsumerWidget {
  const TripPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(tripControllerProvider);
    final c = ref.read(tripControllerProvider.notifier);
    final trips = ref.watch(tripsProvider).value ?? const [];
    final active = ref.watch(activeRouteProvider);
    final online = ref.watch(onlineProvider).value ?? true;
    final tripId = s.from != null && s.to != null ? Trip.idOf(s.from!, s.to!) : null;

    Widget endpoint(String label, Place? p, ValueChanged<Place> set) => Material(
          color: AppColors.bgRaised,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            leading: Icon(label == 'From' ? Icons.trip_origin_outlined : Icons.flag_outlined),
            title: Text(p?.label ?? 'Choose $label'),
            subtitle: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
            trailing: const Icon(Icons.chevron_right_outlined),
            onTap: () async {
              final r = await pickEndpoint(context, label == 'From' ? 'Starting point' : 'Destination');
              if (r != null) set(r);
            },
          ),
        );

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_outlined), onPressed: () => Navigator.of(context).maybePop()),
          const Expanded(child: ScreenHeader(eyebrow: 'Trip planner', title: 'Check your route')),
        ]),
        const SizedBox(height: 12),
        endpoint('From', s.from, c.setFrom),
        const SizedBox(height: 8),
        endpoint('To', s.to, c.setTo),
        const SizedBox(height: 12),
        PillButton(
          label: s.loading ? 'Checking...' : 'Check route & navigate',
          icon: Icons.navigation_outlined,
          expand: true,
          onPressed: s.from == null || s.to == null || s.loading
              ? null
              : () async {
                  await c.check();
                  if (context.mounted && ref.read(tripControllerProvider).hasResult) context.push('/home/trip/navigate');
                },
        ),
        if (s.from != null && s.to != null) const OfflineCard(),
        if (s.loading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (!online)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: StatusBanner(lead: 'You are offline.', text: 'Live routing and place search are unavailable; routes are approximate.')),
        if (s.error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: StatusBanner(lead: 'Check failed.', text: s.error!, color: AppColors.statusCritical, icon: Icons.error_outline)),
        if (s.hasResult) ..._result(context, ref, s, tripId, active),
        if (trips.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Eyebrow('Recent trips'),
          const SizedBox(height: 8),
          for (final t in trips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LightCard(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t.from.label} → ${t.to.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (active?.tripId == t.id) const Text('Active trip', style: TextStyle(fontSize: 12)),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Re-check against current risk',
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: s.loading ? null : () => c.check(from: t.from, to: t.to),
                  ),
                ]),
              ),
            ),
        ],
        const SizedBox(height: 16),
      ]),
    );
  }

  List<Widget> _result(BuildContext context, WidgetRef ref, TripState s, String? tripId, ActiveRoute? active) {
    final o = s.original!;
    final d = s.diverted;
    final all = [...o.points, ...?d?.points];
    String fmt(TripRoute r) => '${r.km.toStringAsFixed(0)} km · ${(r.minutes / 60).floor()}h ${(r.minutes % 60).round()}m';
    return [
      const SizedBox(height: 16),
      if (o.approximate)
        const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: StatusBanner(lead: 'Live routing unavailable.', text: 'Showing an approximate straight-line route.')),
      if (d == null)
        const StatusBanner(lead: 'Route clear.', text: 'No high-risk zones on this route right now.', color: AppColors.statusOk, icon: Icons.check_circle_outline)
      else ...[
        StatusBanner(lead: 'Rerouted —', text: s.reason!, color: AppColors.statusHigh, icon: Icons.alt_route_outlined),
        if (s.stillRisky)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: StatusBanner(
                  lead: 'No fully clear detour found.',
                  text: 'Confirm with local authorities before you leave.',
                  color: AppColors.statusCritical,
                  icon: Icons.warning_amber_outlined)),
      ],
      const SizedBox(height: 12),
      SizedBox(
        height: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FlutterMap(
            key: ValueKey('${tripId}_${all.length}'),
            options: mapOptions(fit: CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.all(40))),
            children: [
              darkTiles,
              hazardZones(d == null ? const [] : s.avoid.map((a) => a.hazard).toSet()),
              PolylineLayer(polylines: [
                Polyline(points: o.points, color: AppColors.statusUnknown, strokeWidth: 4),
                if (d != null) Polyline(points: d.points, color: AppColors.statusOk, strokeWidth: 5),
                for (final a in s.avoid)
                  Polyline(
                      points: a.points,
                      color: AppColors.statusCritical,
                      strokeWidth: 5,
                      pattern: StrokePattern.dashed(segments: [12, 8])),
              ]),
              MarkerLayer(markers: [
                Marker(point: s.from!.pos, width: 32, height: 32, child: const Icon(Icons.trip_origin_outlined, color: AppColors.textOnDark)),
                Marker(point: s.to!.pos, width: 32, height: 32, child: const Icon(Icons.flag_outlined, color: AppColors.accent)),
              ]),
              mapAttribution,
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 4, children: [
        _Legend(AppColors.statusUnknown, 'Original route  ${fmt(o)}'),
        if (d != null) _Legend(AppColors.statusOk, 'Diverted route  ${fmt(d)}'),
        if (s.avoid.isNotEmpty) const _Legend(AppColors.statusCritical, 'Restricted segment (dashed)'),
      ]),
      const SizedBox(height: 8),
      PillButton(
        label: 'Start navigation',
        icon: Icons.navigation_outlined,
        outlined: true,
        expand: true,
        onPressed: () => context.push('/home/trip/navigate'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use for alerts on this trip'),
        subtitle: const Text('Notify me about new hazards along this route.'),
        value: tripId != null && active?.tripId == tripId,
        activeThumbColor: AppColors.accent,
        onChanged: (on) {
          final n = ref.read(activeRouteProvider.notifier);
          on ? n.set(tripId!, s.chosen!.points) : n.clear();
        },
      ),
    ];
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 18, height: 4, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
