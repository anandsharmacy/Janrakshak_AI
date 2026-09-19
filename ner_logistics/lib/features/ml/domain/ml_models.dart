/// ML road-disruption risk as returned by the Supabase RPCs in
/// `supabase/migrations/20260912000003_ml_integration.sql`.
///
/// The sih-ml model scores every corridor road segment once a day; the
/// publisher copies that day into Supabase. These types mirror the RPC JSON so
/// the app and the website show the same versioned prediction.
///
/// Display rules (SRS ML-006/008/011): rank by `riskPercentile`, never present
/// the calibrated probability as a probability, always label replay / stale /
/// unavailable, and keep ML output visibly separate from reports and rules.
library;

enum MlState { live, replay, stale, unavailable }

enum MlTier { none, alert, humanReview }

/// Route-level verdict computed server-side from the matched segments.
enum MlBand { high, review, low, noCoverage }

MlState _state(Object? v) => switch (v) {
      'live' => MlState.live,
      'replay' => MlState.replay,
      'stale' => MlState.stale,
      _ => MlState.unavailable,
    };

MlTier _tier(Object? v) => switch (v) {
      'alert' => MlTier.alert,
      'human_review' => MlTier.humanReview,
      _ => MlTier.none,
    };

MlBand _band(Object? v) => switch (v) {
      'high' => MlBand.high,
      'review' => MlBand.review,
      'low' => MlBand.low,
      _ => MlBand.noCoverage,
    };

double? _num(Object? v) => (v as num?)?.toDouble();

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Which published run an answer came from. Every ML response carries it.
class MlMeta {
  final MlState state;
  final int? runId;
  final DateTime? scoreDate;
  final String? modelVersion;
  final String? bundleHash;
  final DateTime? publishedAt;
  final String? caveat;

  const MlMeta({
    required this.state,
    this.runId,
    this.scoreDate,
    this.modelVersion,
    this.bundleHash,
    this.publishedAt,
    this.caveat,
  });

  static const unavailable = MlMeta(state: MlState.unavailable);

  factory MlMeta.fromJson(Map<String, dynamic> j) => MlMeta(
        state: _state(j['state']),
        runId: (j['run_id'] as num?)?.toInt(),
        scoreDate: _date(j['score_date']),
        modelVersion: j['model_version'] as String?,
        bundleHash: j['bundle_hash'] as String?,
        publishedAt: _date(j['published_at']),
        caveat: j['caveat'] as String?,
      );

  bool get hasData => state != MlState.unavailable;
}

class MlSegment {
  final String segmentId;
  final double? alongM;
  final double lat;
  final double lon;
  final double riskPercentile;
  final MlTier tier;
  final bool steep;

  const MlSegment({
    required this.segmentId,
    required this.lat,
    required this.lon,
    required this.riskPercentile,
    required this.tier,
    this.alongM,
    this.steep = false,
  });

  factory MlSegment.fromJson(Map<String, dynamic> j) => MlSegment(
        segmentId: j['segment_id'] as String,
        alongM: _num(j['along_m']),
        lat: _num(j['lat']) ?? 0,
        lon: _num(j['lon']) ?? 0,
        riskPercentile: _num(j['risk_percentile']) ?? 0,
        tier: _tier(j['tier']),
        steep: j['steep'] == true,
      );
}

class RouteRiskSummary {
  final int matched;
  final int alerts;
  final int reviews;
  final double? maxPercentile;
  final MlBand band;
  final MlSegment? worst;

  const RouteRiskSummary({
    required this.matched,
    required this.alerts,
    required this.reviews,
    required this.band,
    this.maxPercentile,
    this.worst,
  });

  factory RouteRiskSummary.fromJson(Map<String, dynamic>? j) {
    if (j == null) {
      return const RouteRiskSummary(matched: 0, alerts: 0, reviews: 0, band: MlBand.noCoverage);
    }
    final w = j['worst'];
    return RouteRiskSummary(
      matched: (j['n_matched'] as num?)?.toInt() ?? 0,
      alerts: (j['n_alert'] as num?)?.toInt() ?? 0,
      reviews: (j['n_human_review'] as num?)?.toInt() ?? 0,
      maxPercentile: _num(j['max_percentile']),
      band: _band(j['band']),
      worst: w is Map ? MlSegment.fromJson(w.cast<String, dynamic>()) : null,
    );
  }
}

/// ML risk along one line: a stored route, or a line the app planned itself.
class RouteRisk {
  final MlMeta meta;
  final String? routeId;
  final double? lengthM;
  final double coverageFraction;
  final RouteRiskSummary summary;

  /// Alert / review segments ordered by distance from the start of the line.
  final List<MlSegment> segments;

  /// When this came from the on-device cache instead of the network.
  final DateTime? cachedAt;

  const RouteRisk({
    required this.meta,
    required this.summary,
    this.routeId,
    this.lengthM,
    this.coverageFraction = 0,
    this.segments = const [],
    this.cachedAt,
  });

  factory RouteRisk.fromJson(Map<String, dynamic> j, {DateTime? cachedAt}) => RouteRisk(
        meta: MlMeta.fromJson(j),
        routeId: j['route_id'] as String?,
        lengthM: _num(j['route_length_m']),
        coverageFraction: _num(j['coverage_fraction']) ?? 0,
        summary: RouteRiskSummary.fromJson((j['summary'] as Map?)?.cast<String, dynamic>()),
        segments: (j['segments'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => MlSegment.fromJson(m.cast<String, dynamic>()))
            .toList(),
        cachedAt: cachedAt,
      );

  /// The first alert / review segment at least [fromM] metres along the line.
  MlSegment? nextRiskAfter(double fromM) {
    for (final s in segments) {
      if ((s.alongM ?? -1) >= fromM) return s;
    }
    return null;
  }
}

/// A route the signed-in rider is assigned to, with its ML risk.
class AssignedRouteRisk {
  final String shipmentId;
  final String shipmentNumber;
  final String shipmentStatus;
  final String routeId;
  final String? routeNumber;
  final String? routeName;
  final RouteRisk risk;

  const AssignedRouteRisk({
    required this.shipmentId,
    required this.shipmentNumber,
    required this.shipmentStatus,
    required this.routeId,
    required this.risk,
    this.routeNumber,
    this.routeName,
  });
}

/// `get_my_routes_ml_risk()` (riders) or `get_routes_ml_summary()` (officers).
class RoutesRisk {
  final MlMeta meta;
  final List<AssignedRouteRisk> routes;
  final DateTime? cachedAt;

  const RoutesRisk({required this.meta, required this.routes, this.cachedAt});

  factory RoutesRisk.fromJson(Map<String, dynamic> j, {DateTime? cachedAt}) {
    final meta = MlMeta.fromJson(j);
    return RoutesRisk(
      meta: meta,
      cachedAt: cachedAt,
      routes: (j['routes'] as List? ?? const []).whereType<Map>().map((m) {
        final r = m.cast<String, dynamic>();
        return AssignedRouteRisk(
          shipmentId: (r['shipment_id'] as String?) ?? '',
          shipmentNumber: (r['shipment_number'] as String?) ?? '',
          shipmentStatus: (r['shipment_status'] as String?) ?? '',
          routeId: r['route_id'] as String,
          routeNumber: r['route_number'] as String?,
          routeName: r['name'] as String?,
          risk: RouteRisk(
            meta: meta,
            routeId: r['route_id'] as String,
            lengthM: _num(r['route_length_m']),
            coverageFraction: _num(r['coverage_fraction']) ?? 0,
            summary: RouteRiskSummary.fromJson((r['summary'] as Map?)?.cast<String, dynamic>()),
            segments: (r['segments'] as List? ?? const [])
                .whereType<Map>()
                .map((s) => MlSegment.fromJson(s.cast<String, dynamic>()))
                .toList(),
            cachedAt: cachedAt,
          ),
        );
      }).toList(),
    );
  }
}

class TopAlert {
  final MlSegment segment;
  final int tierRank;
  final String? nearPlace;
  final String? nearDistrict;
  final double? nearKm;
  final String? promotedAlertId;

  const TopAlert({
    required this.segment,
    required this.tierRank,
    this.nearPlace,
    this.nearDistrict,
    this.nearKm,
    this.promotedAlertId,
  });
}

/// `get_ml_top_alerts()`: today's top-N for the officer's scope.
class TopAlerts {
  final MlMeta meta;
  final String scope;
  final int capacity;
  final int inTier;
  final List<TopAlert> rows;

  const TopAlerts({
    required this.meta,
    required this.scope,
    required this.capacity,
    required this.inTier,
    required this.rows,
  });

  factory TopAlerts.fromJson(Map<String, dynamic> j) => TopAlerts(
        meta: MlMeta.fromJson(j),
        scope: (j['scope'] as String?) ?? 'region',
        capacity: (j['capacity'] as num?)?.toInt() ?? 0,
        inTier: (j['n_in_tier'] as num?)?.toInt() ?? 0,
        rows: (j['rows'] as List? ?? const []).whereType<Map>().map((m) {
          final r = m.cast<String, dynamic>();
          return TopAlert(
            segment: MlSegment.fromJson(r),
            tierRank: (r['tier_rank'] as num?)?.toInt() ?? 0,
            nearPlace: r['near_place'] as String?,
            nearDistrict: r['near_district'] as String?,
            nearKm: _num(r['near_km']),
            promotedAlertId: r['promoted_alert_id'] as String?,
          );
        }).toList(),
      );
}

// ── Wording shared by every ML widget ────────────────────────────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String mlDate(DateTime? d) => d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Top 0.01%" — the share of corridor roads at least this risky that day.
String topShare(double? percentile) {
  if (percentile == null) return '—';
  final share = (100 - percentile).clamp(0.01, 100.0);
  final text = share < 1
      ? share.toStringAsFixed(2)
      : share < 10
          ? share.toStringAsFixed(1)
          : share.toStringAsFixed(0);
  return 'Top $text%';
}

String mlStateLabel(MlMeta meta) => switch (meta.state) {
      MlState.live => 'Live · ${mlDate(meta.scoreDate)}',
      MlState.replay => 'Replay · rainfall of ${mlDate(meta.scoreDate)}',
      MlState.stale => 'Stale · last ${mlDate(meta.scoreDate)}',
      MlState.unavailable => 'ML unavailable',
    };

String mlTierLabel(MlTier tier) => switch (tier) {
      MlTier.alert => 'High disruption risk',
      MlTier.humanReview => 'Needs officer review',
      MlTier.none => 'Low',
    };

String mlBandLabel(MlBand band) => switch (band) {
      MlBand.high => 'High risk on route',
      MlBand.review => 'Segments need review',
      MlBand.low => 'Low risk',
      MlBand.noCoverage => 'Outside model coverage',
    };
