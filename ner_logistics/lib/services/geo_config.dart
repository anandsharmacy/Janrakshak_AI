/// Endpoints for the routing engine (OSRM) and GIS analytics (GeoServer).
///
/// Override at build time, e.g.
///   flutter run \
///     --dart-define=OSRM_URL=http://10.0.2.2:5000 \
///     --dart-define=GEOSERVER_URL=http://10.0.2.2:8080/geoserver
///
/// (`10.0.2.2` is the host machine from the Android emulator.)
/// See `backend/README.md` for running both services locally.
class GeoConfig {
  /// Defaults to the public OSRM demo server — fine for demos, but it allows
  /// ~1 request/s and no heavy use. Self-host for pilots/production.
  final String osrmUrl;
  final String osrmProfile;

  /// Empty = GeoServer not configured; analytics fall back to on-device
  /// estimates computed from the app's local data.
  final String geoserverUrl;
  final String geoserverWorkspace;

  const GeoConfig({
    required this.osrmUrl,
    this.osrmProfile = 'driving',
    this.geoserverUrl = '',
    this.geoserverWorkspace = 'ner',
  });

  const GeoConfig.fromEnvironment()
      : osrmUrl = const String.fromEnvironment(
          'OSRM_URL',
          defaultValue: 'https://router.project-osrm.org',
        ),
        osrmProfile =
            const String.fromEnvironment('OSRM_PROFILE', defaultValue: 'driving'),
        geoserverUrl = const String.fromEnvironment('GEOSERVER_URL'),
        geoserverWorkspace = const String.fromEnvironment(
          'GEOSERVER_WORKSPACE',
          defaultValue: 'ner',
        );

  bool get geoserverEnabled => geoserverUrl.isNotEmpty;

  bool get usesPublicOsrm => osrmUrl.contains('router.project-osrm.org');
}
