import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'geojson.dart';

class GeoServerException implements Exception {
  final String message;
  const GeoServerException(this.message);
  @override
  String toString() => 'GeoServerException: $message';
}

/// OGC client for a GeoServer workspace (WFS reads, WMS endpoint).
///
/// Spatial filtering uses the WFS `bbox` parameter with an explicit
/// `EPSG:4326` suffix (always lon/lat in GeoServer). CQL spatial predicates
/// are avoided on purpose: their axis order follows each layer's declared
/// CRS, and `DWITHIN` ignores distance units on geographic layers. Precise
/// distance / containment checks happen client-side on the returned GeoJSON.
class GeoServerClient {
  final String baseUrl;
  final String workspace;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsClient;

  GeoServerClient({
    required String baseUrl,
    this.workspace = 'ner',
    this.timeout = const Duration(seconds: 15),
    http.Client? httpClient,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Workspace-scoped WMS endpoint, ready for flutter_map's `baseUrl`.
  String get wmsUrl => '$baseUrl/$workspace/wms?';

  String qualified(String layer) => layer.contains(':') ? layer : '$workspace:$layer';

  /// WFS 2.0 GetFeature as GeoJSON.
  ///
  /// [bbox] is `(west, south, east, north)` in degrees. GeoServer rejects
  /// `bbox` together with [cql], so pass one or the other.
  Future<GeoFeatureCollection> getFeatures(
    String layer, {
    ({double west, double south, double east, double north})? bbox,
    String? cql,
    List<String>? properties,
    int? count,
    String? sortBy,
  }) async {
    if (bbox != null && cql != null) {
      throw ArgumentError('GeoServer does not accept bbox and CQL_FILTER together');
    }
    final params = <String, String>{
      'service': 'WFS',
      'version': '2.0.0',
      'request': 'GetFeature',
      'typeNames': qualified(layer),
      'outputFormat': 'application/json',
      'srsName': 'EPSG:4326',
      if (bbox != null)
        'bbox': '${bbox.west},${bbox.south},${bbox.east},${bbox.north},EPSG:4326',
      'CQL_FILTER': ?cql,
      if (properties != null) 'propertyName': properties.join(','),
      if (count != null) 'count': '$count',
      'sortBy': ?sortBy,
    };
    final uri = Uri.parse('$baseUrl/$workspace/ows').replace(queryParameters: params);

    final http.Response res;
    try {
      res = await _http.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const GeoServerException('Request timed out');
    } catch (e) {
      throw GeoServerException('Network error: $e');
    }

    // Errors come back as HTTP 200/400 with an OWS XML ExceptionReport.
    final body = res.body.trimLeft();
    if (body.startsWith('<')) {
      final text = RegExp(r'<ows:ExceptionText>([\s\S]*?)</ows:ExceptionText>')
              .firstMatch(body)
              ?.group(1)
              ?.trim() ??
          'HTTP ${res.statusCode}';
      throw GeoServerException(text);
    }
    if (res.statusCode != 200) {
      throw GeoServerException('HTTP ${res.statusCode}');
    }
    try {
      return GeoFeatureCollection.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } on FormatException {
      throw const GeoServerException('Response was not GeoJSON');
    }
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
