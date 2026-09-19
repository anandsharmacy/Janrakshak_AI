import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../mock_data/models.dart';
import '../../../services/geo_providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/ml_repository.dart';
import '../domain/ml_models.dart';

/// Ticks whenever a new ML day is published (Realtime on `ml_batch_runs`), so
/// every ML provider below refetches without a manual refresh.
final mlRunTickProvider = StreamProvider<int>((ref) {
  if (ref.watch(authRoleProvider) == null) return const Stream.empty();
  final client = ref.watch(supabaseClientProvider);
  final controller = StreamController<int>();
  var tick = 0;
  final channel = client.channel('ml-batch-runs-${DateTime.now().microsecondsSinceEpoch}')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'ml_batch_runs',
      callback: (_) => controller.add(++tick),
    ).subscribe();
  ref.onDispose(() {
    controller.close();
    client.removeChannel(channel).ignore();
  });
  return controller.stream;
});

/// Signed-in role, or an error the UI renders as "sign in for ML risk".
AppRole _requireRole(Ref ref) {
  ref.watch(mlRunTickProvider);
  final role = ref.watch(authRoleProvider);
  if (role == null) throw const MlSignedOut();
  return role;
}

class MlSignedOut implements Exception {
  const MlSignedOut();
  @override
  String toString() => 'Sign in to see ML road risk.';
}

final mlStatusProvider = FutureProvider<MlMeta>((ref) {
  _requireRole(ref);
  return ref.watch(mlRepositoryProvider).status();
});

/// Riders: every open shipment route assigned to them ("all the relevant routes").
final myRoutesMlRiskProvider = FutureProvider<RoutesRisk>((ref) {
  _requireRole(ref);
  return ref.watch(mlRepositoryProvider).myRoutes();
});

/// Officers: every stored route.
final allRoutesMlRiskProvider = FutureProvider<RoutesRisk>((ref) {
  _requireRole(ref);
  return ref.watch(mlRepositoryProvider).allRoutes();
});

/// Officers: today's top-N segments for their scope (the database picks N).
final mlTopAlertsProvider = FutureProvider<TopAlerts>((ref) {
  _requireRole(ref);
  return ref.watch(mlRepositoryProvider).topAlerts();
});

/// Risk along the rider's active trip as planned by OSRM right now.
final riderTripMlRiskProvider = FutureProvider<RouteRisk>((ref) async {
  _requireRole(ref);
  final plan = await ref.watch(riderTripPlanProvider.future);
  return ref.watch(mlRepositoryProvider).lineRisk(plan.route.geometry);
});
