import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Geometry helpers shared by routing, GIS analytics and map widgets.
///
/// Distances are in metres. Per-segment work uses a local equirectangular
/// projection, which is accurate to well under 1 % at NER segment lengths.
class GeoMath {
  GeoMath._();

  static const earthRadiusM = 6371008.8;
  static const _deg = math.pi / 180;

  static double distanceM(LatLng a, LatLng b) {
    final dLat = (b.latitude - a.latitude) * _deg;
    final dLng = (b.longitude - a.longitude) * _deg;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.latitude * _deg) *
            math.cos(b.latitude * _deg) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Cumulative distance at each vertex of [line] (first entry is 0).
  static List<double> cumulativeM(List<LatLng> line) {
    final out = List<double>.filled(line.length, 0);
    for (var i = 1; i < line.length; i++) {
      out[i] = out[i - 1] + distanceM(line[i - 1], line[i]);
    }
    return out;
  }

  static double lengthM(List<LatLng> line) =>
      line.length < 2 ? 0 : cumulativeM(line).last;

  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  /// Point [m] metres along [line] (clamped to its ends).
  static LatLng pointAtM(List<LatLng> line, double m, [List<double>? cum]) {
    if (line.length == 1) return line.first;
    final c = cum ?? cumulativeM(line);
    if (m <= 0) return line.first;
    if (m >= c.last) return line.last;
    var lo = 0, hi = c.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (c[mid] <= m) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = c[hi] - c[lo];
    return _lerp(line[lo], line[hi], seg == 0 ? 0 : (m - c[lo]) / seg);
  }

  /// Sub-line between [fromM] and [toM] metres, with interpolated ends.
  static List<LatLng> sliceM(List<LatLng> line, double fromM, double toM,
      [List<double>? cum]) {
    final c = cum ?? cumulativeM(line);
    final a = math.max(0.0, math.min(fromM, toM));
    final b = math.min(c.last, math.max(fromM, toM));
    return [
      pointAtM(line, a, c),
      for (var i = 0; i < line.length; i++)
        if (c[i] > a && c[i] < b) line[i],
      pointAtM(line, b, c),
    ];
  }

  /// Nearest position on [line] to [p]: distance along the line and the
  /// perpendicular offset, both in metres.
  static ({double alongM, double offsetM}) project(List<LatLng> line, LatLng p,
      [List<double>? cum]) {
    final c = cum ?? cumulativeM(line);
    var bestOffset = double.infinity;
    var bestAlong = 0.0;
    final kx = math.cos(p.latitude * _deg) * earthRadiusM * _deg;
    const ky = earthRadiusM * _deg;
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1], b = line[i];
      final ax = (a.longitude - p.longitude) * kx, ay = (a.latitude - p.latitude) * ky;
      final bx = (b.longitude - p.longitude) * kx, by = (b.latitude - p.latitude) * ky;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      final px = ax + dx * t, py = ay + dy * t;
      final d = math.sqrt(px * px + py * py);
      if (d < bestOffset) {
        bestOffset = d;
        bestAlong = c[i - 1] + (c[i] - c[i - 1]) * t;
      }
    }
    return (alongM: bestAlong, offsetM: bestOffset);
  }

  static double distanceToLineM(LatLng p, List<LatLng> line) =>
      line.length == 1 ? distanceM(p, line.first) : project(line, p).offsetM;

  /// Smallest distance between any vertex of [a] and the polyline [b].
  static double minDistanceBetweenM(List<LatLng> a, List<LatLng> b) {
    var best = double.infinity;
    for (final p in a) {
      best = math.min(best, distanceToLineM(p, b));
    }
    return best;
  }

  static double bearingDeg(LatLng a, LatLng b) {
    final la1 = a.latitude * _deg, la2 = b.latitude * _deg;
    final dl = (b.longitude - a.longitude) * _deg;
    final y = math.sin(dl) * math.cos(la2);
    final x = math.cos(la1) * math.sin(la2) -
        math.sin(la1) * math.cos(la2) * math.cos(dl);
    return math.atan2(y, x) / _deg;
  }

  /// Destination point [m] metres from [p] on [bearing] degrees.
  static LatLng offsetM(LatLng p, double bearing, double m) {
    final la = p.latitude * _deg, lo = p.longitude * _deg, b = bearing * _deg;
    final d = m / earthRadiusM;
    final la2 = math.asin(
        math.sin(la) * math.cos(d) + math.cos(la) * math.sin(d) * math.cos(b));
    final lo2 = lo +
        math.atan2(math.sin(b) * math.sin(d) * math.cos(la),
            math.cos(d) - math.sin(la) * math.sin(la2));
    return LatLng(la2 / _deg, lo2 / _deg);
  }

  /// Ray-casting test against the outer ring of a polygon.
  static bool pointInRing(LatLng p, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// `(west, south, east, north)` of [points], grown by [padM] metres.
  static ({double west, double south, double east, double north}) bounds(
      Iterable<LatLng> points,
      {double padM = 0}) {
    var w = 180.0, s = 90.0, e = -180.0, n = -90.0;
    for (final p in points) {
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
    }
    final dLat = padM / (earthRadiusM * _deg);
    final dLng = dLat / math.max(0.1, math.cos((s + n) / 2 * _deg));
    return (west: w - dLng, south: s - dLat, east: e + dLng, north: n + dLat);
  }

  /// Douglas–Peucker simplification with a tolerance in metres.
  static List<LatLng> simplify(List<LatLng> line, double toleranceM) {
    if (line.length < 3) return List.of(line);
    final keep = List<bool>.filled(line.length, false)
      ..[0] = true
      ..[line.length - 1] = true;
    final stack = <(int, int)>[(0, line.length - 1)];
    while (stack.isNotEmpty) {
      final (a, b) = stack.removeLast();
      var maxD = 0.0;
      var idx = -1;
      final seg = [line[a], line[b]];
      for (var i = a + 1; i < b; i++) {
        final d = distanceToLineM(line[i], seg);
        if (d > maxD) {
          maxD = d;
          idx = i;
        }
      }
      if (idx != -1 && maxD > toleranceM) {
        keep[idx] = true;
        stack
          ..add((a, idx))
          ..add((idx, b));
      }
    }
    return [for (var i = 0; i < line.length; i++) if (keep[i]) line[i]];
  }

  // ── Encoded polyline (Google algorithm; OSRM `polyline6` = precision 6) ──

  static List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
    final factor = math.pow(10, precision).toDouble();
    final out = <LatLng>[];
    var index = 0, lat = 0, lng = 0;
    int next() {
      var result = 0, shift = 0, b = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }

    while (index < encoded.length) {
      lat += next();
      lng += next();
      out.add(LatLng(lat / factor, lng / factor));
    }
    return out;
  }

  static String encodePolyline(List<LatLng> points, {int precision = 6}) {
    final factor = math.pow(10, precision).toDouble();
    final buf = StringBuffer();
    var pLat = 0, pLng = 0;
    void write(int v) {
      var x = v < 0 ? ~(v << 1) : v << 1;
      while (x >= 0x20) {
        buf.writeCharCode((0x20 | (x & 0x1f)) + 63);
        x >>= 5;
      }
      buf.writeCharCode(x + 63);
    }

    for (final p in points) {
      final lat = (p.latitude * factor).round();
      final lng = (p.longitude * factor).round();
      write(lat - pLat);
      write(lng - pLng);
      pLat = lat;
      pLng = lng;
    }
    return buf.toString();
  }
}
