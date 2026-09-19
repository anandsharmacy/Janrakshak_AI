import 'rider.dart';

/// Rider data access, as seen by [RiderLogisticsService].
///
/// The UI never talks to this directly — it goes through the service — and
/// the service never knows whether the data is mocked or fetched. Swapping
/// [MockRiderDataSource] for a Supabase/REST implementation is a one-line
/// change to `riderDataRepositoryProvider`.
abstract class RiderDataRepository {
  /// Every rider known to the platform (the signed-in one included).
  Future<List<Rider>> fetchRiders();

  /// The rider record for the authenticated account. Identity comes from the
  /// session, never from a hardcoded rider id.
  Future<Rider?> riderForUser({
    required String userId,
    String? officerId,
    String? email,
  });

  /// The road corridor assigned to [riderId], or null when none.
  Future<RiderRoute?> assignedRoute(String riderId);

  /// The incident currently reported on [routeId], or null when the road is clear.
  Future<RouteIncident?> incidentOnRoute(String routeId);
}
