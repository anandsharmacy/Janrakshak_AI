import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/live_rider.dart';

/// Officer-side access to rider positions.
///
/// Initial state comes from the `get_active_riders` RPC (one joined query);
/// deltas arrive through a Realtime channel on `rider_locations` and
/// `rider_profiles`. RLS restricts both to the three officer roles.
class LiveRiderRepository {
  LiveRiderRepository(this._client);

  final SupabaseClient _client;
  static const _timeout = Duration(seconds: 15);

  Future<List<LiveRider>> fetchActive({int staleMinutes = 30}) async {
    final res = await _client
        .rpc('get_active_riders', params: {'p_stale_minutes': staleMinutes})
        .timeout(_timeout);
    return (res as List)
        .whereType<Map>()
        .map((m) => LiveRider.fromRow(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Chronological breadcrumb trail for one rider.
  Future<List<TrailPoint>> fetchTrail(
    String userId, {
    Duration since = const Duration(hours: 2),
    int limit = 500,
  }) async {
    final res = await _client.rpc('get_rider_trail', params: {
      'p_user_id': userId,
      'p_since': DateTime.now().toUtc().subtract(since).toIso8601String(),
      'p_limit': limit,
    }).timeout(_timeout);
    final points = (res as List)
        .whereType<Map>()
        .map((m) => TrailPoint.fromRow(Map<String, dynamic>.from(m)))
        .toList();
    return points.reversed.toList(growable: false);
  }

  /// Opens one channel for both tables. The caller owns the returned channel
  /// and must pass it to [unsubscribe] when done.
  RealtimeChannel subscribe({
    required void Function(Map<String, dynamic> row) onLocation,
    required void Function(Map<String, dynamic> row) onProfile,
    required void Function(RealtimeSubscribeStatus status, Object? error) onStatus,
  }) {
    final channel = _client.channel('live-riders-${DateTime.now().microsecondsSinceEpoch}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rider_locations',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) onLocation(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rider_profiles',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) onProfile(payload.newRecord);
          },
        )
        .subscribe((status, [error]) => onStatus(status, error));
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (_) {
      // Already closed.
    }
  }
}

final liveRiderRepositoryProvider = Provider<LiveRiderRepository>(
  (ref) => LiveRiderRepository(ref.watch(supabaseClientProvider)),
);
