import '../core/demo/demo_mode.dart';
import 'models.dart';

const List<RouteInfo> _demoRoutes = [
  RouteInfo(
    id: 'NH-6',
    name: 'NH-6 Lumding–Sabroom',
    score: 72,
    risk: RiskLevel.caution,
    condition: 'Fair — wet slope Km 22–26',
    incidentCount: 2,
    weather: 'Light rain, 18°C',
    updatedAt: '09:38',
    detail: RouteDetail(
      floodRisk: 'Low',
      landslideRisk: 'Moderate',
      blockage: 'Km 22–26 (active)',
      history: '3 incidents this week',
      recommendedAction: 'Reduce speed, monitor Km 22–26',
    ),
  ),
  RouteInfo(
    id: 'NH-27',
    name: 'NH-27 Shillong–Silchar',
    score: 88,
    risk: RiskLevel.clear,
    condition: 'Good — no active incidents',
    incidentCount: 0,
    weather: 'Partly cloudy, 22°C',
    updatedAt: '09:35',
    detail: RouteDetail(
      floodRisk: 'Low',
      landslideRisk: 'Low',
      blockage: 'None',
      history: '0 incidents this week',
      recommendedAction: 'Proceed normally',
    ),
  ),
  RouteInfo(
    id: 'SH-5',
    name: 'SH-5 Nongpoh–Umiam',
    score: 41,
    risk: RiskLevel.critical,
    condition: 'Poor — Km 31–34 blocked',
    incidentCount: 3,
    weather: 'Heavy rain, 15°C',
    updatedAt: '09:41',
    detail: RouteDetail(
      floodRisk: 'High',
      landslideRisk: 'High',
      blockage: 'Km 31–34 (full blockage)',
      history: '7 incidents this week',
      recommendedAction: 'Avoid — use Lumshnong bypass',
    ),
  ),
  RouteInfo(
    id: 'PMGSY-L',
    name: 'Lumshnong Bypass (PMGSY)',
    score: 93,
    risk: RiskLevel.clear,
    condition: 'Good — clear alternate route',
    incidentCount: 0,
    weather: 'Overcast, 16°C',
    updatedAt: '09:40',
    detail: RouteDetail(
      floodRisk: 'Low',
      landslideRisk: 'Low',
      blockage: 'None',
      history: '1 incident this week',
      recommendedAction: 'Recommended alternate for SH-5',
    ),
  ),
];

/// The sample data while demo mode is on, otherwise empty.
List<RouteInfo> get mockRoutes => DemoMode.enabled ? _demoRoutes : const [];

const List<NearbyIncident> _demoNearbyIncidents = [
  NearbyIncident(
    title: 'Landslide predicted, NH-6',
    place: 'Km 31–34 · 5 km ahead',
    distance: '5.0 km',
    level: RiskLevel.critical,
  ),
  NearbyIncident(
    title: 'Waterlogging on approach road',
    place: 'Dhansiri · Km 22',
    distance: '2.3 km',
    level: RiskLevel.caution,
  ),
  NearbyIncident(
    title: 'Culvert cleared, traffic resumed',
    place: 'Medziphema link',
    distance: '8.1 km',
    level: RiskLevel.clear,
  ),
];

/// The sample data while demo mode is on, otherwise empty.
List<NearbyIncident> get mockNearbyIncidents => DemoMode.enabled ? _demoNearbyIncidents : const [];
