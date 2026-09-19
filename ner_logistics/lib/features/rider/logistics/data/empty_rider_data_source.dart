import '../domain/rider.dart';
import '../domain/rider_data_repository.dart';

/// Used while demo data is off: no riders, routes or incidents.
class EmptyRiderDataSource implements RiderDataRepository {
  const EmptyRiderDataSource();

  @override
  Future<List<Rider>> fetchRiders() async => const [];

  @override
  Future<Rider?> riderForUser({
    required String userId,
    String? officerId,
    String? email,
  }) async =>
      null;

  @override
  Future<RiderRoute?> assignedRoute(String riderId) async => null;

  @override
  Future<RouteIncident?> incidentOnRoute(String routeId) async => null;
}
