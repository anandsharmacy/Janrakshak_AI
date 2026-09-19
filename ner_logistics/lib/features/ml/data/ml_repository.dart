import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/ml_models.dart';

/// Reads ML road-disruption risk through SECURITY DEFINER RPCs — the database
/// decides what each role may see. Riders get their assigned routes and lines
/// they plan; officers get routes, top alerts and promotion.
///
/// Answers are cached on the device so a rider who loses signal keeps the last
/// known risk, labelled with when it was fetched (ML-008).
class MlRepository {
  MlRepository(this._client, {Future<SharedPreferences>? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance();

  final SupabaseClient _client;
  final Future<SharedPreferences> _prefs;

  static const _timeout = Duration(seconds: 15);
  static const _cachePrefix = 'ml.cache.';

  /// Stored lines are simplified to at most this many points before sending.
  static const maxLinePoints = 2000;

  Future<MlMeta> status() async {
    final res = await _client.rpc('ml_status').timeout(_timeout);
    return MlMeta.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Every open shipment route assigned to the signed-in rider.
  Future<RoutesRisk> myRoutes() => _cached(
        'my_routes',
        () => _client.rpc('get_my_routes_ml_risk'),
        (j, at) => RoutesRisk.fromJson(j, cachedAt: at),
      );

  /// Every stored route with geometry (officers).
  Future<RoutesRisk> allRoutes() => _cached(
        'all_routes',
        () => _client.rpc('get_routes_ml_summary'),
        (j, at) => RoutesRisk.fromJson(j, cachedAt: at),
      );

  /// Risk along a line the app planned (the rider's live OSRM trip).
  Future<RouteRisk> lineRisk(List<LatLng> line) {
    final pts = decimate(line, maxLinePoints);
    return _cached(
      'line.${lineKey(pts)}',
      () => _client.rpc('get_route_ml_risk', params: {'p_geojson': lineGeoJson(pts)}),
      (j, at) => RouteRisk.fromJson(j, cachedAt: at),
    );
  }

  Future<TopAlerts> topAlerts() async {
    final res = await _client.rpc('get_ml_top_alerts', params: {'p_tier': 'alert'}).timeout(_timeout);
    return TopAlerts.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Control room / district officer turns one segment into an operational alert.
  Future<String> promote(String segmentId, {int? runId}) async {
    final res = await _client.rpc('promote_ml_alert', params: {
      'p_segment_id': segmentId,
      'p_run_id': ?runId,
    }).timeout(_timeout);
    return res as String;
  }

  /// Audit record of what a user was shown and chose (ML-006 / ML-007).
  /// Best effort: a failed write never blocks the trip.
  Future<void> recordSnapshot({
    required String context,
    required RouteRisk risk,
    String? routeId,
    String? shipmentId,
    List<LatLng>? line,
  }) async {
    try {
      await _client.rpc('record_route_risk_snapshot', params: {
        'p_client_id': const Uuid().v4(),
        'p_context': context,
        'p_run_id': risk.meta.runId,
        'p_route_id': routeId,
        'p_shipment_id': shipmentId,
        'p_route_hash': line == null ? null : lineKey(decimate(line, maxLinePoints)),
        'p_summary': {
          'band': risk.summary.band.name,
          'n_alert': risk.summary.alerts,
          'n_human_review': risk.summary.reviews,
          'max_percentile': risk.summary.maxPercentile,
          'coverage_fraction': risk.coverageFraction,
          'score_date': risk.meta.scoreDate?.toIso8601String(),
          'state': risk.meta.state.name,
          'from_cache': risk.cachedAt != null,
        },
      }).timeout(_timeout);
    } catch (_) {/* audit is best effort on the device */}
  }

  // ── cache ──────────────────────────────────────────────────────────────────

  Future<T> _cached<T>(
    String key,
    Future<dynamic> Function() fetch,
    T Function(Map<String, dynamic> json, DateTime? cachedAt) parse,
  ) async {
    try {
      final res = await fetch().timeout(_timeout);
      final json = Map<String, dynamic>.from(res as Map);
      final prefs = await _prefs;
      await prefs.setString('$_cachePrefix$key',
          jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'json': json}));
      return parse(json, null);
    } catch (e) {
      if (!isOffline(e)) rethrow;
      final raw = (await _prefs).getString('$_cachePrefix$key');
      if (raw == null) rethrow;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      return parse(Map<String, dynamic>.from(saved['json'] as Map),
          DateTime.tryParse(saved['at'] as String? ?? ''));
    }
  }

  /// Network-shaped failures fall back to the cache; authorisation errors don't.
  static bool isOffline(Object e) =>
      e is TimeoutException ||
      e is SocketException ||
      e is AuthRetryableFetchException ||
      e.toString().contains('ClientException') ||
      e.toString().contains('Failed host lookup');
}

// ── pure helpers (unit-tested) ────────────────────────────────────────────────

/// Keeps the first and last point and evenly spaced points between.
List<LatLng> decimate(List<LatLng> line, int maxPoints) {
  if (line.length <= maxPoints) return line;
  final step = (line.length - 1) / (maxPoints - 1);
  return [for (var i = 0; i < maxPoints; i++) line[(i * step).round()]];
}

Map<String, dynamic> lineGeoJson(List<LatLng> line) => {
      'type': 'LineString',
      'coordinates': [
        for (final p in line)
          [double.parse(p.longitude.toStringAsFixed(6)), double.parse(p.latitude.toStringAsFixed(6))],
      ],
    };

/// Stable short key for a line (cache key and audit route hash).
String lineKey(List<LatLng> line) {
  var h = 0x811c9dc5;
  for (final p in line) {
    for (final v in [p.latitude, p.longitude]) {
      h ^= (v * 1e5).round() & 0xffffffff;
      h = (h * 0x01000193) & 0xffffffff;
    }
  }
  return '${line.length}-${h.toRadixString(16)}';
}

final mlRepositoryProvider = Provider<MlRepository>(
  (ref) => MlRepository(ref.watch(supabaseClientProvider)),
);
