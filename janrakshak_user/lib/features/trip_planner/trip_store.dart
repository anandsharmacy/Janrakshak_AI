import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/providers.dart';
import '../../data/store.dart';

class Trip {
  const Trip(this.id, this.from, this.to);
  final String id;
  final Place from, to;

  static String idOf(Place a, Place b) => '${a.pos.latitude},${a.pos.longitude}>${b.pos.latitude},${b.pos.longitude}';

  Map<String, dynamic> toJson() => {'id': id, 'from': from.toJson(), 'to': to.toJson()};
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(j['id'], Place.fromJson(j['from']), Place.fromJson(j['to']));
}

/// Recent trips, newest first (Hive keys are insertion-ordered ints).
final tripsProvider = StreamProvider<List<Trip>>((ref) async* {
  List<Trip> read() => [
        for (final v in Store.trips.values.toList().reversed) Trip.fromJson(jsonDecode(v)),
      ];
  yield read();
  yield* Store.trips.watch().map((_) => read());
});

Future<void> saveTrip(Place from, Place to) async {
  final id = Trip.idOf(from, to);
  final dup = Store.trips.keys.where((k) => (jsonDecode(Store.trips.get(k)!) as Map)['id'] == id).toList();
  await Store.trips.deleteAll(dup);
  await Store.trips.add(jsonEncode(Trip(id, from, to).toJson()));
  if (Store.trips.length > 10) await Store.trips.delete(Store.trips.keys.first);
}

/// The trip whose route drives "Active Trip Route" alerts and notifications.
class ActiveRoute {
  const ActiveRoute(this.tripId, this.points);
  final String tripId;
  final List<LatLng> points;
}

class ActiveRouteNotifier extends Notifier<ActiveRoute?> {
  static const _key = 'active_route';

  @override
  ActiveRoute? build() {
    final raw = Store.settings.get(_key);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return ActiveRoute(j['id'], [for (final p in j['pts']) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())]);
  }

  /// Keeps at most ~300 points. // ponytail: on 3000 km+ routes spacing nears the smallest hazard radius (10 km) and a graze could be missed.
  Future<void> set(String tripId, List<LatLng> points) async {
    final step = (points.length / 300).ceil().clamp(1, points.length);
    final thin = [for (var i = 0; i < points.length; i += step) points[i], points.last];
    state = ActiveRoute(tripId, thin);
    await Store.settings.put(_key, jsonEncode({'id': tripId, 'pts': [for (final p in thin) [p.latitude, p.longitude]]}));
  }

  Future<void> clear() async {
    state = null;
    await Store.settings.delete(_key);
  }
}

final activeRouteProvider = NotifierProvider<ActiveRouteNotifier, ActiveRoute?>(ActiveRouteNotifier.new);
