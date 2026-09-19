import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/feed.dart';
import '../../data/providers.dart';
import '../../data/seed_data.dart';

class MapRangeNotifier extends Notifier<MapRange> {
  @override
  MapRange build() => MapRange.live;
  void set(MapRange r) => state = r;
}

final mapRangeProvider = NotifierProvider<MapRangeNotifier, MapRange>(MapRangeNotifier.new);

/// The tapped / searched location. `place` is coordinates-only until reverse geocoding finishes.
class MapSelectionNotifier extends Notifier<Place?> {
  @override
  Place? build() => null;

  Future<void> select(LatLng p, {Place? known}) async {
    state = known ?? Place(pos: p);
    if (known != null) return;
    final resolved = await reverseGeocode(p);
    if (state?.pos == p) state = resolved; // ignore if the user has already tapped elsewhere
  }

  void clear() => state = null;
}

final mapSelectionProvider = NotifierProvider<MapSelectionNotifier, Place?>(MapSelectionNotifier.new);

final areaMetricsProvider = Provider<AreaMetrics?>((ref) {
  final p = ref.watch(mapSelectionProvider);
  if (p == null) return null;
  return areaMetrics(p.pos, p.state, p.district ?? p.name ?? 'Selected area', ref.watch(mapRangeProvider), ref.watch(hazardsProvider));
});
