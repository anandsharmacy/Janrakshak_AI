import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../data/hazard.dart';
import '../data/offline_tiles.dart';
import '../data/taxonomy.dart';
import '../theme/app_theme.dart';

const indiaCenter = LatLng(22.5, 80.0);

const kCartoDarkUrl = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

/// Base map layer builder.
/// Returns a high-performance dark raster TileLayer as basemap.
/// If PMTiles vector provider is initialized, overlays VectorTileLayer on top while retaining
/// the raster tile basemap for areas outside the local PMTiles extent.
Widget buildDarkTiles() {
  final baseRaster = TileLayer(
    urlTemplate: kCartoDarkUrl,
    subdomains: const ['a', 'b', 'c', 'd'],
    maxZoom: 19,
    userAgentPackageName: 'com.janrakshak.janrakshak_user',
  );

  if (OfflineTiles.theme != null && OfflineTiles.provider != null) {
    return Stack(
      children: [
        baseRaster,
        VectorTileLayer(
          tileProviders: TileProviders({'openmaptiles': OfflineTiles.provider!}),
          theme: OfflineTiles.theme!,
          maximumZoom: 18,
        ),
      ],
    );
  }
  return baseRaster;
}

Widget get darkTiles => buildDarkTiles();

final mapAttribution = SimpleAttributionWidget(
  source: Text(offlineMapsEnabled ? kAttribution : 'OpenStreetMap contributors'),
  backgroundColor: Color(0xCC0F1E33),
);

MapOptions mapOptions({
  LatLng center = indiaCenter,
  double zoom = 4.6,
  CameraFit? fit,
  void Function(TapPosition, LatLng)? onTap,
  VoidCallback? onMapReady,
  void Function(MapCamera, bool)? onPositionChanged,
}) =>
    MapOptions(
      initialCenter: center,
      initialZoom: zoom,
      initialCameraFit: fit,
      backgroundColor: AppColors.bgDark,
      // Vector tiles are stored up to kPmtilesMaxZoom and overzoomed after that; five extra levels is plenty.
      maxZoom: OfflineTiles.provider != null ? kPmtilesMaxZoom + 5.0 : null,
      onTap: onTap,
      onMapReady: onMapReady,
      onPositionChanged: onPositionChanged,
      // Vector tiles are stored up to kPmtilesMaxZoom and overzoomed after that; five extra levels is plenty.
      maxZoom: OfflineTiles.provider != null ? kPmtilesMaxZoom + 5.0 : null,
      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
    );

/// Severity-coloured incident markers; the icon carries the incident type, not just colour.
MarkerLayer hazardMarkers(Iterable<Hazard> hs, {void Function(Hazard)? onTap}) => MarkerLayer(markers: [
      for (final h in hs)
        if (h.center != null)
        Marker(
          point: h.center!,
          width: 40,
          height: 40,
          child: Semantics(
            label: '${h.severity.label} ${h.type} in ${h.district}',
            button: true,
            child: GestureDetector(
              onTap: onTap == null ? null : () => onTap(h),
              child: Container(
                decoration: BoxDecoration(
                    color: h.severity.color, shape: BoxShape.circle, border: Border.all(color: AppColors.textOnDark, width: 2)),
                child: Icon(incidentIcon(h.type), size: 20, color: AppColors.textOnDark),
              ),
            ),
          ),
        ),
    ]);

CircleLayer hazardZones(Iterable<Hazard> hs) => CircleLayer(circles: [
      for (final h in hs)
        if (h.center != null)
        CircleMarker(
          point: h.center!,
          radius: h.radiusKm * 1000,
          useRadiusInMeter: true,
          color: h.severity.color.withAlpha(45),
          borderColor: h.severity.color,
          borderStrokeWidth: 1.5,
        ),
    ]);
