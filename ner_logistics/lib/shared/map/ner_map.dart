import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'map_models.dart';
import 'ner_geo.dart';

export 'map_models.dart';

enum NerMapStyle { street, terrain }

/// Pan limit for every map — Siliguri corridor to Arunachal / Mizoram.
final _regionBounds = LatLngBounds(NerGeo.regionSouthWest, NerGeo.regionNorthEast);

// ═════════════════════════════════════════════════════════════════════════════
// NerMap
// ═════════════════════════════════════════════════════════════════════════════

/// NerMap — OpenStreetMap-backed situation map (flutter_map).
///
/// Non-interactive maps ignore pointer input entirely so they can sit inside
/// scroll views and tappable cards (e.g. "tap to expand" previews).
class NerMap extends StatefulWidget {
  final List<MapRoute> routes;
  final List<MapIncident> incidents;
  final List<MapVehicle> vehicles;
  final List<MapZone> zones;
  final List<MapPoi> pois;

  /// Points the camera frames on first load and when recentred.
  final List<LatLng> fitPoints;
  final EdgeInsets fitPadding;
  final double maxFitZoom;

  /// Change this value to reframe the camera onto [fitPoints].
  final Object? fitKey;

  final bool interactive;
  final bool showControls;
  final bool showRouteLabels;
  final VoidCallback? onExpand;
  final ValueChanged<String>? onIncidentTap;

  /// Long-press on the map (interactive maps only) — used for GeoServer
  /// "inspect this location" queries.
  final ValueChanged<LatLng>? onLongPress;

  /// GeoServer WMS layers drawn between the base map and the vector overlays.
  final List<WmsOverlay> wmsOverlays;
  /// Uses route overlays and the downloaded region boundary without requesting
  /// remote tiles. A future MAPOG tile provider can replace [_offlineLayer].
  final bool offlineMode;
  final String? offlineRegionName;

  const NerMap({
    super.key,
    required this.fitPoints,
    this.routes = const [],
    this.incidents = const [],
    this.vehicles = const [],
    this.zones = const [],
    this.pois = const [],
    this.fitPadding = const EdgeInsets.all(28),
    this.maxFitZoom = 12,
    this.fitKey,
    this.interactive = true,
    this.showControls = false,
    this.showRouteLabels = true,
    this.onExpand,
    this.onIncidentTap,
    this.onLongPress,
    this.wmsOverlays = const [],
    this.offlineMode = false,
    this.offlineRegionName,
  });

  @override
  State<NerMap> createState() => _NerMapState();
}

class _NerMapState extends State<NerMap> {
  final _controller = MapController();
  NerMapStyle _style = NerMapStyle.street;
  bool _ready = false;
  Size _size = Size.zero;

  CameraFit get _fit => CameraFit.coordinates(
        coordinates:
            widget.fitPoints.isEmpty ? const [NerGeo.guwahati] : widget.fitPoints,
        padding: _paddingFor(_size),
        maxZoom: widget.maxFitZoom,
      );

  /// Scales [NerMap.fitPadding] down on short/narrow maps — padding larger
  /// than the viewport makes flutter_map compute a NaN zoom.
  EdgeInsets _paddingFor(Size size) {
    final p = widget.fitPadding;
    if (size.isEmpty) return p;
    final sx = p.horizontal > size.width * 0.6 ? size.width * 0.6 / p.horizontal : 1.0;
    final sy = p.vertical > size.height * 0.6 ? size.height * 0.6 / p.vertical : 1.0;
    return EdgeInsets.fromLTRB(p.left * sx, p.top * sy, p.right * sx, p.bottom * sy);
  }

  @override
  void didUpdateWidget(NerMap old) {
    super.didUpdateWidget(old);
    if (widget.fitKey != old.fitKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recenter());
    }
  }

  void _recenter() {
    if (mounted && _ready) _controller.fitCamera(_fit);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // The pre-fit camera must already satisfy cameraConstraint; the
        // flutter_map default centre (Kyiv) trips its assertion.
        initialCenter: widget.fitPoints.isEmpty
            ? NerGeo.guwahati
            : widget.fitPoints.first,
        initialZoom: 7,
        initialCameraFit: _fit,
        minZoom: 5,
        maxZoom: 17,
        backgroundColor: const Color(0xFFE9ECE4),
        cameraConstraint:
            CameraConstraint.containCenter(bounds: _regionBounds),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onMapReady: () => _ready = true,
        onLongPress: widget.onLongPress == null
            ? null
            : (_, point) => widget.onLongPress!(point),
      ),
      children: [
        if (widget.offlineMode) _offlineLayer() else _tileLayer(),
        if (!widget.offlineMode)
          for (final o in widget.wmsOverlays) _wmsLayer(o),
        if (widget.zones.isNotEmpty)
          CircleLayer(circles: [for (final z in widget.zones) _zoneCircle(z)]),
        PolylineLayer(polylines: _polylines()),
        MarkerLayer(markers: _markers()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(builder: (context, constraints) {
            _size = constraints.biggest;
            final map = _buildMap();
            return widget.interactive ? map : IgnorePointer(child: map);
          }),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: _Attribution(style: _style),
        ),
        if (widget.offlineMode)
          Positioned(
            left: 12,
            top: 12,
            child: _OfflineMapBadge(regionName: widget.offlineRegionName),
          ),
        if (widget.showControls)
          Positioned(
            right: 12,
            bottom: 28,
            child: _MapControls(
              style: _style,
              onRecenter: _recenter,
              onToggleStyle: () => setState(() => _style =
                  _style == NerMapStyle.street
                      ? NerMapStyle.terrain
                      : NerMapStyle.street),
              onExpand: widget.onExpand,
            ),
          ),
      ],
    );
  }

  // ── Layers ─────────────────────────────────────────────────────────────────

  TileLayer _tileLayer() {
    final street = _style == NerMapStyle.street;
    return TileLayer(
      key: ValueKey(_style),
      urlTemplate: street
          ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
          : 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: street ? const [] : const ['a', 'b', 'c'],
      maxNativeZoom: street ? 19 : 17,
      userAgentPackageName: 'in.gov.ner.ner_logistics',
    );
  }

  TileLayer _wmsLayer(WmsOverlay o) {
    return TileLayer(
      key: ValueKey(o.cacheKey),
      wmsOptions: WMSTileLayerOptions(
        baseUrl: o.url,
        layers: [o.layer],
        styles: [if (o.style != null) o.style!],
        transparent: true,
        otherParameters: {if (o.cql != null) 'CQL_FILTER': o.cql!},
      ),
      tileDisplay: TileDisplay.instantaneous(opacity: o.opacity),
      userAgentPackageName: 'in.gov.ner.ner_logistics',
    );
  }

  Widget _offlineLayer() {
    return const ColoredBox(
      color: Color(0xFFE6ECE4),
      child: CustomPaint(
        painter: _OfflineGridPainter(),
        child: SizedBox.expand(),
      ),
    );
  }

  CircleMarker _zoneCircle(MapZone z) {
    final c = _zoneColor(z.kind);
    return CircleMarker(
      point: z.center,
      radius: z.radiusMeters,
      useRadiusInMeter: true,
      color: c.withValues(alpha: z.kind == MapZoneKind.safe ? 0.08 : 0.16),
      borderColor: c.withValues(alpha: 0.8),
      borderStrokeWidth: z.kind == MapZoneKind.safe ? 2 : 1,
    );
  }

  List<Polyline> _polylines() {
    // Draw de-emphasised lines first so risk colours sit on top.
    final sorted = [...widget.routes]
      ..sort((a, b) => _lineZ(a.tone).compareTo(_lineZ(b.tone)));
    return [
      for (final r in sorted)
        Polyline(
          points: r.points,
          color: _lineColor(r.tone),
          strokeWidth: 4.5,
          borderColor: Colors.white.withValues(alpha: 0.9),
          borderStrokeWidth: _dashed(r.tone) ? 0 : 1.5,
          pattern: _dashed(r.tone)
              ? StrokePattern.dashed(segments: const [10, 7])
              : const StrokePattern.solid(),
        ),
    ];
  }

  List<Marker> _markers() {
    return [
      if (widget.showRouteLabels)
        for (final r in widget.routes)
          if (r.label != null)
            Marker(
              point: NerGeo.pointAlong(r.points, 0.5),
              width: 56,
              height: 20,
              child: _RouteLabel(text: r.label!, color: _lineColor(r.tone)),
            ),
      for (final z in widget.zones)
        if (z.kind != MapZoneKind.impact)
          Marker(
            point: z.center,
            width: 22,
            height: 22,
            child: _ZoneBadge(zone: z),
          ),
      for (final p in widget.pois)
        Marker(point: p.point, width: 24, height: 24, child: _PoiPin(poi: p)),
      for (final v in widget.vehicles)
        Marker(
          point: v.point,
          width: v.self ? 34 : v.live ? (v.selected ? 38 : 30) : 24,
          height: v.self ? 34 : v.live ? (v.selected ? 38 : 30) : 24,
          child: _VehiclePin(vehicle: v),
        ),
      for (final i in widget.incidents)
        Marker(
          point: i.point,
          width: 30,
          height: 30,
          child: _IncidentPin(
            incident: i,
            onTap: widget.onIncidentTap == null
                ? null
                : () => widget.onIncidentTap!(i.id),
          ),
        ),
    ];
  }
}

class _OfflineMapBadge extends StatelessWidget {
  final String? regionName;
  const _OfflineMapBadge({this.regionName});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.deepGreen700.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.download_done_outlined,
                size: 15, color: AppColors.deepGreen700),
            const SizedBox(width: 6),
            Text(
              'Offline map${regionName == null ? '' : ' · $regionName'}',
              style: AppTextStyles.captionSemibold.copyWith(
                color: AppColors.deepGreen700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineGridPainter extends CustomPainter {
  const _OfflineGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB7C8B8).withOpacity(0.45)
      ..strokeWidth = 1;
    const spacing = 34.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OfflineGridPainter oldDelegate) => false;
}

// ═════════════════════════════════════════════════════════════════════════════
// Styling helpers
// ═════════════════════════════════════════════════════════════════════════════

const _avoidedGrey = Color(0xFF9AA0A8);

Color _lineColor(MapLineTone t) => switch (t) {
      MapLineTone.clear => AppColors.deepGreen700,
      MapLineTone.caution => AppColors.saffron600,
      MapLineTone.critical => AppColors.signalRed700,
      MapLineTone.avoided => _avoidedGrey,
      MapLineTone.candidate => AppColors.navy900,
      MapLineTone.travelled => AppColors.navy900.withValues(alpha: 0.35),
    };

bool _dashed(MapLineTone t) =>
    t == MapLineTone.avoided || t == MapLineTone.candidate;

int _lineZ(MapLineTone t) => switch (t) {
      MapLineTone.avoided => 0,
      MapLineTone.travelled => 1,
      MapLineTone.candidate => 2,
      MapLineTone.clear => 3,
      MapLineTone.caution => 4,
      MapLineTone.critical => 5,
    };

Color _zoneColor(MapZoneKind k) => switch (k) {
      MapZoneKind.safe => AppColors.navy900,
      MapZoneKind.flood => AppColors.saffron600,
      MapZoneKind.landslide => AppColors.signalRed700,
      MapZoneKind.impact => AppColors.signalRed700,
    };

Color _severityColor(Priority p) => switch (p) {
      Priority.critical => AppColors.signalRed700,
      Priority.high => AppColors.saffron600,
      Priority.medium => AppColors.saffron600,
      Priority.low => AppColors.slate500,
    };

IconData _incidentIcon(IncidentType t) => switch (t) {
      IncidentType.flood => Icons.water_drop_outlined,
      IncidentType.landslide => Icons.landslide_outlined,
      IncidentType.roadBlockage => Icons.block,
      IncidentType.accident => Icons.car_crash_outlined,
      IncidentType.infraDamage => Icons.construction_outlined,
      IncidentType.other => Icons.warning_amber_outlined,
    };

// ═════════════════════════════════════════════════════════════════════════════
// Marker widgets
// ═════════════════════════════════════════════════════════════════════════════

/// Tap-to-show label; long-press on touch is non-obvious for field users.
Widget _tip(String message, Widget child) => Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      preferBelow: false,
      child: child,
    );

class _RouteLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _RouteLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(
          text,
          style: AppTextStyles.caption.copyWith(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: AppColors.navy900,
          ),
        ),
      ),
    );
  }
}

class _IncidentPin extends StatelessWidget {
  final MapIncident incident;
  final VoidCallback? onTap;
  const _IncidentPin({required this.incident, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = incident.resolved
        ? AppColors.deepGreen700
        : _severityColor(incident.severity);
    final pin = Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        incident.resolved ? Icons.check : _incidentIcon(incident.type),
        size: 15,
        color: Colors.white,
      ),
    );
    if (onTap != null) {
      return Semantics(
        button: true,
        label: incident.label,
        child: GestureDetector(onTap: onTap, child: pin),
      );
    }
    return _tip(incident.label, pin);
  }
}

class _VehiclePin extends StatelessWidget {
  final MapVehicle vehicle;
  const _VehiclePin({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    if (vehicle.live) return _livePin();
    if (vehicle.self) {
      return _tip(
        vehicle.label,
        Container(
          decoration: BoxDecoration(
            color: AppColors.navy900,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy900.withValues(alpha: 0.35),
                blurRadius: 10,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const Icon(Icons.navigation, size: 16, color: Colors.white),
        ),
      );
    }
    final ring = switch (vehicle.risk) {
      Priority.critical => AppColors.signalRed700,
      Priority.high => AppColors.saffron600,
      _ => Colors.white,
    };
    return _tip(
      vehicle.label,
      Container(
        decoration: BoxDecoration(
          color: AppColors.gold,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: ring == Colors.white ? 2 : 2.5),
        ),
        child: const Icon(Icons.local_shipping, size: 12, color: AppColors.navy900),
      ),
    );
  }

  /// Live rider from the mobile app: colour = freshness/risk, rotation =
  /// heading, gold ring = selected. Stale riders fade to grey so an officer
  /// never mistakes an old fix for a current one.
  Widget _livePin() {
    final fill = vehicle.stale
        ? _avoidedGrey
        : switch (vehicle.risk) {
            Priority.critical => AppColors.signalRed700,
            Priority.high => AppColors.saffron600,
            _ => AppColors.navy900,
          };
    final ring = vehicle.selected ? AppColors.gold : Colors.white;
    final heading = vehicle.heading;
    final icon = heading == null
        ? const Icon(Icons.local_shipping, size: 14, color: Colors.white)
        : Transform.rotate(
            angle: heading * math.pi / 180,
            child: const Icon(Icons.navigation, size: 15, color: Colors.white),
          );
    final pin = Container(
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: vehicle.selected ? 3 : 2.5),
        boxShadow: vehicle.stale
            ? const []
            : [
                BoxShadow(
                  color: fill.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
      ),
      child: Center(child: icon),
    );
    final onTap = vehicle.onTap;
    if (onTap != null) {
      return Semantics(
        button: true,
        label: vehicle.label,
        child: GestureDetector(onTap: onTap, child: pin),
      );
    }
    return _tip(vehicle.label, pin);
  }
}

class _ZoneBadge extends StatelessWidget {
  final MapZone zone;
  const _ZoneBadge({required this.zone});

  @override
  Widget build(BuildContext context) {
    final icon = switch (zone.kind) {
      MapZoneKind.safe => Icons.shield_outlined,
      MapZoneKind.flood => Icons.water_outlined,
      MapZoneKind.landslide => Icons.landslide_outlined,
      MapZoneKind.impact => Icons.warning_outlined,
    };
    final color = _zoneColor(zone.kind);
    return _tip(
      zone.label,
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Icon(icon, size: 12, color: color),
      ),
    );
  }
}

class _PoiPin extends StatelessWidget {
  final MapPoi poi;
  const _PoiPin({required this.poi});

  @override
  Widget build(BuildContext context) {
    final icon = switch (poi.kind) {
      MapPoiKind.depot => Icons.warehouse_outlined,
      MapPoiKind.bridge => Icons.foundation,
      MapPoiKind.destination => Icons.flag,
    };
    return _tip(
      poi.label,
      Container(
        decoration: BoxDecoration(
          color: AppColors.navy900,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Chrome
// ═════════════════════════════════════════════════════════════════════════════

class _MapControls extends StatelessWidget {
  final NerMapStyle style;
  final VoidCallback onRecenter;
  final VoidCallback onToggleStyle;
  final VoidCallback? onExpand;
  const _MapControls({
    required this.style,
    required this.onRecenter,
    required this.onToggleStyle,
    this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          color: AppColors.navy900,
          onPressed: onPressed,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.my_location_outlined, 'Recenter', onRecenter),
          const Divider(color: AppColors.hairline, height: 1),
          button(
            style == NerMapStyle.street
                ? Icons.terrain_outlined
                : Icons.map_outlined,
            style == NerMapStyle.street ? 'Terrain view' : 'Street view',
            onToggleStyle,
          ),
          if (onExpand != null) ...[
            const Divider(color: AppColors.hairline, height: 1),
            button(Icons.open_in_full, 'Expand map', onExpand!),
          ],
        ],
      ),
    );
  }
}

/// OSM / OpenTopoMap attribution — required by both tile usage policies.
class _Attribution extends StatelessWidget {
  final NerMapStyle style;
  const _Attribution({required this.style});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.openstreetmap.org/copyright'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: Colors.white.withValues(alpha: 0.8),
        child: Text(
          style == NerMapStyle.street
              ? '© OpenStreetMap'
              : '© OpenStreetMap · OpenTopoMap',
          style: AppTextStyles.caption.copyWith(
            fontSize: 9,
            height: 1.3,
            color: AppColors.slate500,
          ),
        ),
      ),
    );
  }
}
