import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/offline_tiles.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dark_map.dart';
import '../../widgets/widgets.dart';
import 'navigation_controller.dart';

IconData maneuverIcon(String type, String? modifier) {
  if (type == 'arrive') return Icons.flag_outlined;
  if (type.contains('roundabout') || type == 'rotary') return Icons.roundabout_left_outlined;
  return switch (modifier) {
    'left' => Icons.turn_left_outlined,
    'right' => Icons.turn_right_outlined,
    'slight left' => Icons.turn_slight_left_outlined,
    'slight right' => Icons.turn_slight_right_outlined,
    'sharp left' => Icons.turn_sharp_left_outlined,
    'sharp right' => Icons.turn_sharp_right_outlined,
    'uturn' => Icons.u_turn_left_outlined,
    _ => Icons.straight_outlined,
  };
}

String formatDistance(double m) {
  if (m < 100) return '${(m / 10).round() * 10} m';
  if (m < 1000) return '${(m / 50).round() * 50} m';
  return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';
}

class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});
  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final _map = MapController();
  bool _ready = false, _follow = true;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _recenter(LatLng p) {
    if (_ready && _follow) _map.move(p, navZoom);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(navControllerProvider);
    ref.listen(navControllerProvider.select((n) => n.pos), (_, p) {
      if (p != null) _recenter(p);
    });
    final pr = s.progress;
    final next = pr?.next;
    final t = Theme.of(context).textTheme;
    final pad = MediaQuery.paddingOf(context);
    final remainingM = pr?.remainingM ?? s.route.km * 1000;
    final minutes = s.route.km == 0 ? 0.0 : remainingM / 1000 / s.route.km * s.route.minutes;
    final eta = TimeOfDay.fromDateTime(DateTime.now().add(Duration(minutes: minutes.round()))).format(context);

    final (icon, headline, line) = s.arrived
        ? (Icons.flag_outlined, 'Arrived', 'You have reached ${s.destination.label}.')
        : next != null
            ? (maneuverIcon(next.type, next.modifier), formatDistance(pr!.toNextM!), next.instruction)
            : (Icons.straight_outlined, pr == null ? 'Waiting for GPS' : 'Follow the route', 'Towards ${s.destination.label}');

    final line0 = s.route.points;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: mapOptions(
            center: s.pos ?? line0.first,
            zoom: navZoom,
            onMapReady: () => _ready = true,
            onPositionChanged: (_, byGesture) {
              if (byGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            darkTiles,
            hazardZones({for (final a in s.avoid) a.hazard}),
            PolylineLayer(polylines: [
              Polyline(points: line0, color: s.reason != null ? AppColors.statusOk : AppColors.accent, strokeWidth: 6),
              for (final a in s.avoid)
                Polyline(points: a.points, color: AppColors.statusCritical, strokeWidth: 6, pattern: StrokePattern.dashed(segments: [12, 8])),
            ]),
            MarkerLayer(markers: [
              Marker(point: s.destination.pos, width: 36, height: 36, child: const Icon(Icons.flag_outlined, color: AppColors.accent, size: 32)),
              if (s.pos != null)
                Marker(
                  point: s.pos!,
                  width: 26,
                  height: 26,
                  child: Container(
                    decoration: BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: AppColors.textOnDark, width: 3)),
                  ),
                ),
            ]),
            mapAttribution,
          ],
        ),
        Positioned(
          top: pad.top + 8,
          left: 12,
          right: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Material(
              color: AppColors.bgDark,
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Semantics(
                  liveRegion: true,
                  label: '$headline. $line',
                  child: Row(children: [
                    Icon(icon, size: 44, color: AppColors.accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(headline, style: t.headlineMedium),
                        Text(line, style: t.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            if (s.rerouting)
              const Padding(padding: EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Rerouting...', text: 'You left the route; finding a safe way.', icon: Icons.alt_route_outlined)),
            if (s.rerouteFailed)
              const Padding(padding: EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Could not reroute.', text: 'Head back to the highlighted route.', color: AppColors.statusCritical, icon: Icons.error_outline)),
            if (s.reason != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Rerouted —', text: s.reason!, color: AppColors.statusHigh, icon: Icons.alt_route_outlined)),
            if (s.route.approximate)
              const Padding(padding: EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Live routing unavailable.', text: 'Straight-line guidance only.')),
          ]),
        ),
        if (!_follow && s.pos != null)
          Positioned(
            right: 12,
            bottom: 132 + pad.bottom,
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Recenter',
              onPressed: () {
                setState(() => _follow = true);
                _recenter(s.pos!);
              },
              child: const Icon(Icons.my_location_outlined),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: AppColors.bgDark,
            elevation: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + pad.bottom),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(formatDistance(remainingM), style: t.headlineMedium),
                    Text(s.arrived ? 'Arrived' : '${minutes.round()} min · ETA $eta', style: t.bodyMedium?.copyWith(color: AppTheme.mutedOnDark)),
                  ]),
                ),
                PillButton(
                  label: s.arrived ? 'Done' : 'End',
                  icon: Icons.close_outlined,
                  outlined: !s.arrived,
                  color: s.arrived ? AppColors.accent : AppColors.statusCritical,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
