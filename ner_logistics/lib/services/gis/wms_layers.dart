import '../../shared/map/map_models.dart';
import 'geoserver_client.dart';

/// GeoServer WMS overlays for the situation maps (styles published by
/// `backend/geoserver/publish.sh`). Empty when GeoServer isn't configured,
/// in which case the maps draw their local risk circles instead.
List<WmsOverlay> nerWmsOverlays(
  GeoServerClient? gs, {
  bool flood = false,
  bool landslide = false,
  bool heatmap = false,
}) {
  if (gs == null) return const [];
  WmsOverlay zones(String kind) => WmsOverlay(
        url: gs.wmsUrl,
        layer: gs.qualified('risk_zones'),
        style: gs.qualified('ner_risk_zones'),
        cql: "kind='$kind'",
      );
  return [
    if (flood) zones('flood'),
    if (landslide) zones('landslide'),
    if (heatmap)
      WmsOverlay(
        url: gs.wmsUrl,
        layer: gs.qualified('incidents'),
        style: gs.qualified('ner_incident_heatmap'),
        opacity: 0.8,
      ),
  ];
}
