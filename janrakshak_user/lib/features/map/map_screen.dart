import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/feed.dart';
import '../../data/providers.dart';
import '../../data/seed_data.dart';
import '../../data/taxonomy.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dark_map.dart';
import '../../widgets/widgets.dart';
import 'map_state.dart';
import 'status_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  bool _legend = false, _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  void _zoom(double d) => _map.move(_map.camera.center, (_map.camera.zoom + d).clamp(3, 18));

  Future<void> _go(LatLng p, {Place? known, double zoom = 10}) async {
    _map.move(p, zoom);
    await ref.read(mapSelectionProvider.notifier).select(p, known: known);
  }

  Future<void> _submitSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    final hit = await geocodeQuery(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchError = hit == null ? 'No match for "$q". Try another name, or tap the map.' : null;
    });
    if (hit != null) {
      FocusScope.of(context).unfocus();
      await _go(hit.pos);
    }
  }

  Future<void> _locate() async {
    final pos = await currentPosition();
    if (!mounted) return;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location is off or permission was denied.')));
      return;
    }
    await _go(LatLng(pos.latitude, pos.longitude), zoom: 12);
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(mapSelectionProvider);
    final range = ref.watch(mapRangeProvider);
    final online = ref.watch(onlineProvider).value ?? true;
    final pad = MediaQuery.paddingOf(context);
    final hazards = ref.watch(hazardsProvider);

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: mapOptions(onTap: (_, p) => _go(p, zoom: _map.camera.zoom.clamp(8, 18))),
        children: [
          darkTiles,
          hazardZones(hazards),
          hazardMarkers(hazards, onTap: (h) => _go(h.center!, known: Place(pos: h.center!, state: h.state, district: h.district))),
          if (sel != null)
            MarkerLayer(markers: [
              Marker(point: sel.pos, width: 40, height: 40, alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on_outlined, size: 40, color: AppColors.accent)),
            ]),
          mapAttribution,
        ],
      ),
      Positioned(
        top: pad.top + 8, left: 12, right: 12,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: _submitSearch,
            decoration: InputDecoration(
              hintText: 'Search a place, e.g. Port Blair',
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: _searching
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(tooltip: 'Search', icon: const Icon(Icons.arrow_forward_outlined), onPressed: () => _submitSearch(_search.text)),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<MapRange>(
            segments: [for (final r in MapRange.values) ButtonSegment(value: r, label: Text(r.label))],
            selected: {range},
            showSelectedIcon: false,
            onSelectionChanged: (v) => ref.read(mapRangeProvider.notifier).set(v.first),
          ),
          if (_searchError != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Not found.', text: _searchError!, color: AppColors.statusCritical, icon: Icons.error_outline)),
          if (!online)
            const Padding(padding: EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Offline.', text: 'Live risk data unavailable; map tiles and search may not load.')),
          if (kSampleData)
            const Padding(padding: EdgeInsets.only(top: 8), child: StatusBanner(lead: 'Sample metrics.', text: 'Incident markers are live; risk scores, weather and facilities are illustrative.')),
          if (_legend) const Padding(padding: EdgeInsets.only(top: 8), child: _Legend()),
        ]),
      ),
      Positioned(
        right: 12,
        top: 0,
        bottom: 0,
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(heroTag: null, tooltip: 'Legend', onPressed: () => setState(() => _legend = !_legend), child: const Icon(Icons.layers_outlined)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: null, tooltip: 'Zoom in', onPressed: () => _zoom(1), child: const Icon(Icons.add_outlined)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: null, tooltip: 'Zoom out', onPressed: () => _zoom(-1), child: const Icon(Icons.remove_outlined)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: null, tooltip: 'My location', onPressed: _locate, child: const Icon(Icons.my_location_outlined)),
          ]),
        ),
      ),
      if (sel != null) const StatusSheet(),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.bgDark.withAlpha(235), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Incident severity'),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [for (final s in Severity.values) SeverityIndicator(s)]),
      ]),
    );
  }
}
