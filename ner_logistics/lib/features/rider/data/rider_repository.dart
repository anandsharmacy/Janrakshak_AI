import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/rider_context.dart';
import '../domain/rider_location_point.dart';

/// Rider-side Supabase access. Everything goes through SECURITY DEFINER RPCs
/// defined in `supabase/migrations/20260912000002_rider_tracking.sql` so the
/// role check and idempotency live server-side.
class RiderRepository {
  RiderRepository(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 15);

  /// Uploads a batch (oldest first). Returns the number of points accepted.
  /// Safe to retry: `client_id` de-duplicates on the server.
  Future<int> syncLocations(List<RiderLocationPoint> points) async {
    if (points.isEmpty) return 0;
    final res = await _client
        .rpc('sync_rider_locations', params: {
          'p_points': points.map((p) => p.toRpcJson()).toList(),
        })
        .timeout(_timeout);
    return (res as num?)?.toInt() ?? points.length;
  }

  Future<void> setDuty(bool onDuty, {String? vehicleRegistration, String? vehicleType}) async {
    await _client.rpc('set_rider_duty', params: {
      'p_on_duty': onDuty,
      if (vehicleRegistration != null) 'p_vehicle_registration': vehicleRegistration,
      if (vehicleType != null) 'p_vehicle_type': vehicleType,
    }).timeout(_timeout);
  }

  Future<RiderContext?> fetchContext() async {
    final res = await _client.rpc('get_my_rider_context').timeout(_timeout);
    if (res == null) return null;
    return RiderContext.fromJson(Map<String, dynamic>.from(res as Map));
  }
}

final riderRepositoryProvider = Provider<RiderRepository>(
  (ref) => RiderRepository(ref.watch(supabaseClientProvider)),
);

/// Rider profile, vehicle and assigned shipments from Supabase.
/// Refresh with `ref.invalidate(riderContextProvider)`.
final riderContextProvider = FutureProvider<RiderContext?>(
  (ref) => ref.watch(riderRepositoryProvider).fetchContext(),
);
