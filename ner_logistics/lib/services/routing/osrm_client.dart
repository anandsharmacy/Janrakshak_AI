import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'osrm_models.dart';

class OsrmException implements Exception {
  /// OSRM response code (`NoRoute`, `NoSegment`, `TooBig`, …) or `Network`.
  final String code;
  final String message;
  const OsrmException(this.code, this.message);

  @override
  String toString() => 'OsrmException($code): $message';
}

/// Thin client for the OSRM HTTP API (`/route`, `/nearest`).
///
/// Requests are serialised and spaced by [minInterval] — the public demo
/// server allows ~1 request/s — and identical requests are served from an
/// in-memory cache.
class OsrmClient {
  final String baseUrl;
  final String profile;
  final Duration minInterval;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;

  final _cache = <String, List<OsrmRoute>>{};
  static const _cacheLimit = 64;
  Future<void> _gate = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  OsrmClient({
    required String baseUrl,
    this.profile = 'driving',
    Duration? minInterval,
    this.timeout = const Duration(seconds: 15),
    http.Client? httpClient,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        minInterval = minInterval ??
            (baseUrl.contains('router.project-osrm.org')
                ? const Duration(milliseconds: 1100)
                : Duration.zero),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static String _coords(List<LatLng> pts) => pts
      .map((p) =>
          '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
      .join(';');

  /// Driving route through [waypoints]. With [alternatives] > 0 OSRM may
  /// return extra routes (first is always the fastest).
  Future<List<OsrmRoute>> route(
    List<LatLng> waypoints, {
    int alternatives = 0,
    bool steps = true,
  }) async {
    if (waypoints.length < 2) {
      throw const OsrmException('InvalidQuery', 'Need at least 2 waypoints');
    }
    final url = '$baseUrl/route/v1/$profile/${_coords(waypoints)}'
        '?overview=full&geometries=polyline6&steps=$steps'
        '&alternatives=${alternatives > 0 ? alternatives : 'false'}';
    final cached = _cache[url];
    if (cached != null) return cached;

    final json = await _get(url);
    final routes = [
      for (final r in (json['routes'] as List? ?? const []))
        OsrmRoute.fromJson(r as Map<String, dynamic>),
    ];
    if (routes.isEmpty) throw const OsrmException('NoRoute', 'No route found');
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[url] = routes;
    return routes;
  }

  /// Snaps [point] to the nearest routable road.
  Future<({LatLng location, double distanceM, String name})> nearest(
      LatLng point) async {
    final json =
        await _get('$baseUrl/nearest/v1/$profile/${_coords([point])}?number=1');
    final w = (json['waypoints'] as List).first as Map<String, dynamic>;
    final loc = w['location'] as List;
    return (
      location: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
      distanceM: (w['distance'] as num).toDouble(),
      name: w['name'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final previous = _gate;
    final done = Completer<void>();
    _gate = done.future;
    try {
      await previous;
      final wait = minInterval - DateTime.now().difference(_last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _last = DateTime.now();

      final http.Response res;
      try {
        res = await _http.get(Uri.parse(url), headers: const {
          'User-Agent': 'ner_logistics (in.gov.ner.ner_logistics)',
        }).timeout(timeout);
      } on TimeoutException {
        throw const OsrmException('Network', 'OSRM request timed out');
      } catch (e) {
        throw OsrmException('Network', e.toString());
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        throw OsrmException('BadResponse', 'HTTP ${res.statusCode}');
      }
      final code = json['code'] as String? ?? 'BadResponse';
      if (code != 'Ok') {
        throw OsrmException(code, json['message'] as String? ?? code);
      }
      return json;
    } finally {
      done.complete();
    }
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
