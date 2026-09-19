import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth.dart';
import 'hazard.dart';
import 'providers.dart';
import 'region_data.dart';
import 'store.dart';
import 'taxonomy.dart';

const _cacheKey = 'feed_cache';

// DB enum values (disaster_type_enum / incident_type_enum) -> the app's incident taxonomy.
const _dbType = {
  'flood': 'Floods',
  'flash_flood': 'Floods',
  'landslide': 'Landslides',
  'earthquake': 'Earthquakes',
  'cyclone': 'Cyclones',
  'bridge_damage': 'Infrastructure Damage',
  'road_blockage': 'Infrastructure Damage',
  'road_block': 'Infrastructure Damage',
  'infrastructure_damage': 'Infrastructure Damage',
};

Hazard hazardFromRow(Map<String, dynamic> j) {
  final raw = j['incident_type'] as String?;
  final lat = (j['lat'] as num?)?.toDouble(), lng = (j['lng'] as num?)?.toDouble();
  final state = j['state'] as String?;
  return Hazard(
    id: j['id'] as String,
    type: raw == null ? 'Alert' : _dbType[raw] ?? 'Other',
    severity: Severity.values.asNameMap()[j['severity']] ?? Severity.moderate,
    state: RegionData.matchState(state) ?? state ?? '',
    district: j['district'] as String? ?? '',
    center: lat == null || lng == null ? null : LatLng(lat, lng),
    radiusKm: (j['radius_km'] as num?)?.toDouble() ?? 10,
    summary: j['summary'] as String? ?? '',
    source: switch (j['source_kind']) {
      'officer' => ReportSource.fieldOfficer,
      'community' => ReportSource.community,
      _ => ReportSource.automated,
    },
    at: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

List<Hazard> _parse(String json) =>
    [for (final r in jsonDecode(json) as List) hazardFromRow(r as Map<String, dynamic>)];

class Feed {
  const Feed(this.hazards, {this.stale = false});
  final List<Hazard> hazards;
  final bool stale; // live fetch failed; showing the last cached copy (or nothing)
}

/// Live citizen feed via the get_citizen_feed RPC; cached in Hive so the last update survives offline launches.
/// Re-fetched every 2 minutes, on sign-in, and when connectivity returns.
// ponytail: polling; switch to Realtime on alerts/disaster_events if sub-minute latency matters.
final hazardFeedProvider = FutureProvider<Feed>((ref) async {
  final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final uid = ref.watch(sessionProvider.select((s) => s.value?.user.id));
  ref.watch(onlineProvider.select((o) => o.value));
  if (uid == null) return const Feed([]);
  try {
    final rows = await Supabase.instance.client.rpc('get_citizen_feed', params: {'p_limit': 200});
    final json = jsonEncode(rows);
    await Store.settings.put(_cacheKey, json);
    return Feed(_parse(json));
  } catch (_) {
    final cached = Store.settings.get(_cacheKey);
    return Feed(cached == null ? const [] : _parse(cached), stale: true);
  }
});

final hazardsProvider = Provider<List<Hazard>>((ref) => ref.watch(hazardFeedProvider).value?.hazards ?? const []);
