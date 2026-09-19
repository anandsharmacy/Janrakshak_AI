import '../core/demo/demo_mode.dart';
import 'models.dart';

const _demoOfflineMapRegions = [
  OfflineMapRegion(
    id: 'map-ri-bhoi',
    name: 'Ri Bhoi · NH-6 corridor',
    coverage: 'Nongpoh · Umsning · Byrnihat',
    size: '186 MB',
    updatedAt: '12 Sep 2026',
    status: OfflineMapRegionStatus.available,
    downloadProgress: 100,
  ),
  OfflineMapRegion(
    id: 'map-guwahati',
    name: 'Guwahati depot area',
    coverage: 'Guwahati · Sonapur · Jorabat',
    size: '142 MB',
    updatedAt: '08 Sep 2026',
    status: OfflineMapRegionStatus.updateAvailable,
  ),
];

/// The sample data while demo mode is on, otherwise empty.
List<OfflineMapRegion> get mockOfflineMapRegions => DemoMode.enabled ? _demoOfflineMapRegions : const [];
