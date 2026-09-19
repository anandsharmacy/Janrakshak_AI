import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/demo/demo_mode.dart';
import '../ml/presentation/ml_widgets.dart';
import '../../mock_data/mock_officers.dart';
import '../../mock_data/models.dart';
import '../../services/geo_providers.dart';
import '../../services/gis/wms_layers.dart';
import '../../services/routing/closure_impact.dart';
import '../../shared/analytics/geo_analytics_widgets.dart';
import '../../shared/map/ner_geo.dart';
import '../../shared/map/ner_map.dart';
import '../../shared/widgets/widgets.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../auth/application/auth_controller.dart';
import '../profile/profile_sheet.dart';
import '../tracking/application/live_riders_controller.dart';
import '../tracking/presentation/live_riders_screen.dart';
import 'control_drawer.dart';

const _kDistricts = <DistrictSummary>[
  DistrictSummary(
    name: 'Barpeta',
    state: 'Assam',
    risk: Priority.critical,
    accessScore: 82,
    incidentCount: 5,
    criticalCount: 2,
    blockedRoutes: 3,
    logisticsNote: 'Flooding affecting NH-27 corridor',
    statusLabel: 'Active Response',
  ),
  DistrictSummary(
    name: 'Dimapur',
    state: 'Nagaland',
    risk: Priority.high,
    accessScore: 71,
    incidentCount: 4,
    criticalCount: 1,
    blockedRoutes: 2,
    logisticsNote: 'Landslide risk near NH-29',
    statusLabel: 'Monitoring',
  ),
  DistrictSummary(
    name: 'Silchar',
    state: 'Assam',
    risk: Priority.high,
    accessScore: 68,
    incidentCount: 3,
    criticalCount: 1,
    blockedRoutes: 1,
    logisticsNote: 'Route restrictions on NH-306',
    statusLabel: 'At Risk',
  ),
  DistrictSummary(
    name: 'Shillong',
    state: 'Meghalaya',
    risk: Priority.medium,
    accessScore: 52,
    incidentCount: 3,
    criticalCount: 0,
    blockedRoutes: 1,
    logisticsNote: 'Infra work on NH-6',
    statusLabel: 'Restricted',
  ),
  DistrictSummary(
    name: 'Tawang',
    state: 'Arunachal',
    risk: Priority.high,
    accessScore: 74,
    incidentCount: 4,
    criticalCount: 1,
    blockedRoutes: 2,
    logisticsNote: 'NH-13 closed — landslide zone',
    statusLabel: 'Escalated',
  ),
  DistrictSummary(
    name: 'Jorabat',
    state: 'Assam',
    risk: Priority.low,
    accessScore: 28,
    incidentCount: 2,
    criticalCount: 0,
    blockedRoutes: 0,
    logisticsNote: 'All routes operational',
    statusLabel: 'Clear',
  ),
];

const _kFleet = <FleetVehicle>[
  FleetVehicle(
    id: 'TRK-1042',
    route: 'NH-27 › Guwahati → Siliguri',
    destination: 'Siliguri Hub',
    statusLabel: 'In Transit',
    risk: Priority.medium,
    eta: 'ETA 3h 12m',
  ),
  FleetVehicle(
    id: 'TRK-2091',
    route: 'NH-306 › Guwahati → Silchar',
    destination: 'Silchar Depot',
    statusLabel: 'Delayed',
    risk: Priority.high,
    eta: 'ETA +2h 40m',
  ),
  FleetVehicle(
    id: 'TRK-3107',
    route: 'NH-40 › Shillong → Jorabat',
    destination: 'Jorabat Yard',
    statusLabel: 'In Transit',
    risk: Priority.low,
    eta: 'ETA 1h 05m',
  ),
  FleetVehicle(
    id: 'TRK-4215',
    route: 'NH-10 › Gangtok → Siliguri',
    destination: 'Siliguri Hub',
    statusLabel: 'At Risk',
    risk: Priority.high,
    eta: 'ETA Hold',
  ),
  FleetVehicle(
    id: 'TRK-5088',
    route: 'NH-2 › Dimapur → Kohima',
    destination: 'Kohima Depot',
    statusLabel: 'Stopped',
    risk: Priority.critical,
    eta: 'ETA Unknown',
  ),
  FleetVehicle(
    id: 'TRK-6012',
    route: 'NH-6 › Shillong → Guwahati',
    destination: 'Guwahati Hub',
    statusLabel: 'In Transit',
    risk: Priority.medium,
    eta: 'ETA 2h 30m',
  ),
];

const _kRoutes = [
  (id: 'NH-27', name: 'Barpeta Road', distance: '228 km', status: RouteStatus.blocked, score: 88, weather: 'Heavy Rain', eta: 'Blocked', delay: 'Indefinite', updated: '12 min ago'),
  (id: 'NH-2', name: 'Dimapur Bypass', distance: '184 km', status: RouteStatus.restricted, score: 62, weather: 'Cloudy', eta: '5h 10m', delay: '+1h 30m', updated: '8 min ago'),
  (id: 'NH-306', name: 'Silchar Corridor', distance: '312 km', status: RouteStatus.restricted, score: 68, weather: 'Showers', eta: '7h 45m', delay: '+2h 15m', updated: '15 min ago'),
  (id: 'NH-6', name: 'Shillong Hwy', distance: '196 km', status: RouteStatus.restricted, score: 54, weather: 'Fog', eta: '5h 30m', delay: '+45m', updated: '22 min ago'),
  (id: 'NH-13', name: 'Tawang Pass', distance: '248 km', status: RouteStatus.closed, score: 92, weather: 'Snow', eta: 'Closed', delay: '24h+', updated: '1h ago'),
  (id: 'NH-40', name: 'Jorabat Link', distance: '92 km', status: RouteStatus.open, score: 22, weather: 'Clear', eta: '2h 15m', delay: 'On time', updated: '5 min ago'),
  (id: 'NH-10', name: 'Siliguri Route', distance: '156 km', status: RouteStatus.open, score: 28, weather: 'Partly Cloudy', eta: '3h 50m', delay: 'On time', updated: '3 min ago'),
];

const _kIncidents = [
  (id: 'INC-4471', type: IncidentType.flood, typeLabel: 'Flood', location: 'Barpeta, Assam', route: 'NH-27', severity: Priority.critical, reporter: 'FO Rajiv K.', time: '34 min ago', verified: true, assignedOfficer: 'DO Das, Barpeta', statusLabel: 'Active'),
  (id: 'INC-4460', type: IncidentType.landslide, typeLabel: 'Landslide', location: 'Tawang, Arunachal', route: 'NH-13', severity: Priority.critical, reporter: 'FO Amit S.', time: '1h 12m ago', verified: true, assignedOfficer: 'DO Norbu, Tawang', statusLabel: 'Escalated'),
  (id: 'INC-4455', type: IncidentType.roadBlockage, typeLabel: 'Logistics Block', location: 'Dimapur, Nagaland', route: 'NH-2', severity: Priority.high, reporter: 'FO Priya M.', time: '1h 48m ago', verified: true, assignedOfficer: 'DO Ao, Dimapur', statusLabel: 'Active'),
  (id: 'INC-4448', type: IncidentType.infraDamage, typeLabel: 'Infra Damage', location: 'Silchar, Assam', route: 'NH-306', severity: Priority.high, reporter: 'FO Rina D.', time: '2h 20m ago', verified: true, assignedOfficer: 'DO Barman, Silchar', statusLabel: 'Pending'),
  (id: 'INC-4440', type: IncidentType.accident, typeLabel: 'Vehicle Accident', location: 'Shillong, Meghalaya', route: 'NH-6', severity: Priority.medium, reporter: 'FO Neha G.', time: '3h 05m ago', verified: true, assignedOfficer: 'DO Lyngdoh, Shillong', statusLabel: 'Pending'),
  (id: 'INC-4432', type: IncidentType.other, typeLabel: 'Weather Alert', location: 'Jorabat, Assam', route: 'NH-40', severity: Priority.low, reporter: 'System', time: '4h 18m ago', verified: false, assignedOfficer: 'Unassigned', statusLabel: 'Resolved'),
  (id: 'INC-4425', type: IncidentType.flood, typeLabel: 'Flood Scare', location: 'Siliguri, WB', route: 'NH-10', severity: Priority.medium, reporter: 'FO Tarun P.', time: '6h 02m ago', verified: true, assignedOfficer: 'DO Ghosh, Siliguri', statusLabel: 'Resolved'),
];

const _kAlerts = [
  (id: 'ALT-101', severity: AlertSeverity.critical, title: 'NH-27 Barpeta — Flood waters rising', description: 'Flood level exceeds 1.2m red line across 4 km of NH-27. All traffic must divert via NH-152.', distance: '42 km ahead', time: '8 min ago', source: 'NER Flood Control', action: 'Divert all convoys via NH-152 immediately.'),
  (id: 'ALT-098', severity: AlertSeverity.critical, title: 'NH-13 Tawang — Landslide red zone', description: 'Geological sensors indicate 72% probability of major slide within 6 hours. Zone 18 km from Tawang.', distance: '18 km ahead', time: '22 min ago', source: 'AI Predictive Model', action: 'Halt all northbound convoys on NH-13.'),
  (id: 'ALT-095', severity: AlertSeverity.high, title: 'NH-2 Dimapur — Route restricted', description: 'Single-lane traffic for 11 km due to shoulder collapse. Expect 45-60 min delays.', distance: '11 km stretch', time: '41 min ago', source: 'DO Ao, Dimapur', action: 'Plan extended ETA, deploy pilot vehicles.'),
  (id: 'ALT-091', severity: AlertSeverity.high, title: 'Silchar Depot — Receiving bay congestion', description: 'Inbound arrivals exceeding offload capacity by 38%. Queue time 4+ hours.', distance: 'Silchar, Assam', time: '1h 08m ago', source: 'Logistics Ops', action: 'Redirect 2 convoys to Karimganj yard.'),
  (id: 'ALT-087', severity: AlertSeverity.moderate, title: 'NH-6 Shillong — Fog advisory', description: 'Visibility <200m on Shillong Pass 0500-0900 hrs tomorrow.', distance: 'Shillong Hwy', time: '2h 14m ago', source: 'IMD Guwahati', action: 'Schedule early departures after 0900.'),
  (id: 'ALT-082', severity: AlertSeverity.moderate, title: 'TRK-2091 — Driver fatigue alert', description: 'Telematics indicates 14h continuous operation for TRK-2091.', distance: 'TRK-2091 · NH-306', time: '2h 40m ago', source: 'Fleet Telematics', action: 'Schedule 1h rest stop at next halt.'),
  (id: 'ALT-078', severity: AlertSeverity.info, title: 'NH-40 Jorabat — Road works complete', description: 'Infra work on NH-40 km 42-48 cleared. Full 2-lane access restored.', distance: 'Jorabat, Assam', time: '3h 55m ago', source: 'NER PWD', action: 'No action required.'),
  (id: 'ALT-074', severity: AlertSeverity.info, title: 'Weekly fleet sync complete', description: '62/62 active vehicles synced at 0600 roll call. No overdue maintenance.', distance: 'Region-wide', time: '5h 12m ago', source: 'Fleet Ops', action: 'No action required.'),
];

enum IncTab { all, pending, active, escalated, resolved }
enum RouteTab { all, open, restricted, blocked, closed }
enum AlertTab { all, critical, high, moderate, info }

class ControlRoomShell extends ConsumerStatefulWidget {
  final VoidCallback onSignOut;
  const ControlRoomShell({super.key, required this.onSignOut});

  @override
  ConsumerState<ControlRoomShell> createState() => _ControlRoomShellState();
}

class _ControlRoomShellState extends ConsumerState<ControlRoomShell> {
  ControlNav _nav = ControlNav.command;
  bool _drawerOpen = false;
  bool _profileOpen = false;
  int _alertsBadge = 5;

  bool _mapExpanded = false;
  bool _simulating = false;
  String? _simulatedRoute;
  bool _simSheetOpen = false;
  bool _refreshing = false;
  bool _refreshed = false;
  bool _filtersOpen = false;

  IncTab _incTab = IncTab.all;
  RouteTab _routeTab = RouteTab.all;
  AlertTab _alertTab = AlertTab.all;
  String? _severityFilter;
  String? _typeFilter;
  int? _detailIncident;
  final Set<String> _ackedAlerts = {};

  Map<String, bool> _layers = {
    'Roads': true,
    'Incidents': true,
    'FloodRisk': true,
    'Landslide': true,
    'Logistics': false,
    'Infrastructure': false,
  };
  String _riskLevel = 'All';
  String _timeRange = 'Now';

  @override
  void initState() {
    super.initState();
    // Incident density heatmap needs GeoServer's vec:Heatmap transformation.
    if (ref.read(geoConfigProvider).geoserverEnabled) _layers['Heatmap'] = false;
  }

  void _go(ControlNav d) => setState(() { _nav = d; _drawerOpen = false; });

  /// Signed-in operator from Supabase; demo identity as fallback.
  Officer get _officer => ref.watch(currentProfileProvider)?.toOfficer() ?? controlOfficer;

  String _pageLabel() {
    switch (_nav) {
      case ControlNav.command:    return 'Command Center';
      case ControlNav.map:        return 'Regional Map';
      case ControlNav.logistics:  return 'Live Logistics';
      case ControlNav.riders:     return 'Live Riders';
      case ControlNav.incidents:  return 'Incidents';
      case ControlNav.routes:     return 'Routes';
      case ControlNav.ai:         return 'AI Predictions';
      case ControlNav.alerts:     return 'Alerts';
      case ControlNav.analytics:  return 'Analytics';
    }
  }

  Future<void> _doRefresh() async {
    setState(() { _refreshing = true; _refreshed = false; });
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() { _refreshing = false; _refreshed = true; });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() { _refreshed = false; });
  }

  ChipTone _routeTone(RouteStatus s) {
    switch (s) {
      case RouteStatus.open: return ChipTone.clear;
      case RouteStatus.restricted: return ChipTone.saffron;
      case RouteStatus.blocked: return ChipTone.critical;
      case RouteStatus.closed: return ChipTone.critical;
    }
  }

  ChipTone _alertTone(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.critical: return ChipTone.critical;
      case AlertSeverity.high: return ChipTone.saffron;
      case AlertSeverity.moderate: return ChipTone.navy;
      case AlertSeverity.info: return ChipTone.muted;
    }
  }

  BannerTone _bannerTone(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.critical: return BannerTone.critical;
      case AlertSeverity.high: return BannerTone.caution;
      case AlertSeverity.moderate: return BannerTone.caution;
      case AlertSeverity.info: return BannerTone.clear;
    }
  }

  Color _leftAccent(Priority p) => switch (p) {
    Priority.critical => AppColors.signalRed700,
    Priority.high => AppColors.saffron600,
    _ => Colors.transparent,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F1),
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: 'Regional Control Center · ${_pageLabel()}',
                subtitle: 'Janrakshak AI › Regional Control › ${_pageLabel()}',
                roleInitials: 'CO',
                alertCount: _alertsBadge,
                isOffline: false,
                onMenu: () => setState(() => _drawerOpen = true),
                onBell: () => _go(ControlNav.alerts),
                onAvatar: () => setState(() => _profileOpen = true),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
          if (_drawerOpen)
            Positioned.fill(
              child: ControlDrawer(
                current: _nav,
                alertBadge: _alertsBadge,
                onNavigate: _go,
                onClose: () => setState(() => _drawerOpen = false),
                onSignOut: widget.onSignOut,
              ),
            ),
          if (_profileOpen)
            Positioned.fill(
              child: ProfileSheet(
                role: AppRole.control,
                officer: _officer,
                onClose: () => setState(() => _profileOpen = false),
                onSignOut: widget.onSignOut,
              ),
            ),
          if (_mapExpanded)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.6),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _regionalMap(interactive: true, applyFilters: true),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: AppColors.navy900, foregroundColor: Colors.white),
                            onPressed: () => setState(() => _mapExpanded = false),
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ),
                        const Positioned(left: 12, bottom: 12, child: MapLegend()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_simSheetOpen)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.4),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 500),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                            child: Row(
                              children: [
                                Text('Simulate Route Closure', style: AppTextStyles.sectionHeading),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => setState(() => _simSheetOpen = false),
                                  icon: const Icon(Icons.close, color: AppColors.slate500),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: AppColors.hairline),
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.all(12),
                              itemCount: demoOnly(_kRoutes).length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final r = demoOnly(_kRoutes)[i];
                                return CardSurface(
                                  onTap: () {
                                    setState(() {
                                      _simulatedRoute = '${r.id} ${r.name}';
                                      _simulating = true;
                                      _simSheetOpen = false;
                                    });
                                  },
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(8)),
                                        alignment: Alignment.center,
                                        child: Text(r.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.navy900)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${r.id} · ${r.name}', style: AppTextStyles.cardTitle),
                                            Text('${r.distance} · ${r.weather}', style: AppTextStyles.meta),
                                          ],
                                        ),
                                      ),
                                      StatusChip(tone: _routeTone(r.status), label: r.status.name.toUpperCase()),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Maps ────────────────────────────────────────────────────────

  MapLineTone _mapTone(String route) {
    final id = NerGeo.routeIdOf(route);
    if (_simulating && _simulatedRoute != null && NerGeo.routeIdOf(_simulatedRoute!) == id) {
      return MapLineTone.critical;
    }
    for (final r in demoOnly(_kRoutes)) {
      if (r.id == id) return NerGeo.toneForStatus(r.status);
    }
    return MapLineTone.clear;
  }

  /// Lowest incident severity shown for the Map tab's risk-level filter.
  Priority get _riskFloor => switch (_riskLevel) {
        'Critical' => Priority.critical,
        'High' => Priority.high,
        'Moderate' => Priority.medium,
        _ => Priority.low,
      };

  void _openIncidentById(String id) {
    final i = demoOnly(_kIncidents).indexWhere((e) => e.id == id);
    if (i >= 0) _openIncidentSheet(i);
  }

  /// Closure being simulated, routed through OSRM for affected convoys.
  ClosureQuery? get _closureQuery => _simulating && _simulatedRoute != null
      ? ClosureQuery(
          routeId: NerGeo.routeIdOf(_simulatedRoute!),
          convoys: ConvoyTrip.fromFleet(demoOnly(_kFleet)),
        )
      : null;

  /// Regional situation map. Previews are static (tap passes through to the
  /// parent card); [applyFilters] honours the Map tab's layer / risk filters.
  /// Risk zones come from GeoServer WMS when configured, else local circles.
  Widget _regionalMap({
    double? height,
    bool interactive = false,
    bool applyFilters = false,
    bool showIncidents = true,
    VoidCallback? onExpand,
  }) {
    bool on(String layer) => !applyFilters || (_layers[layer] ?? false);
    final routes = NerGeo.routes({for (final r in demoOnly(_kRoutes)) r.id: _mapTone(r.id)});
    final gs = ref.watch(geoServerClientProvider);
    return SizedBox(
      height: height,
      child: NerMap(
        interactive: interactive,
        showControls: interactive,
        showRouteLabels: interactive,
        onExpand: onExpand,
        onIncidentTap: interactive ? _openIncidentById : null,
        onLongPress: interactive ? (p) => showLocationInsight(context, p) : null,
        fitPoints: [for (final r in routes) ...r.points],
        fitPadding: EdgeInsets.all(interactive ? 32 : 10),
        routes: [
          if (on('Roads')) ...routes,
          if (interactive) ...closureRoutes(ref, _closureQuery),
        ],
        wmsOverlays: applyFilters
            ? nerWmsOverlays(gs,
                flood: on('FloodRisk'),
                landslide: on('Landslide'),
                heatmap: on('Heatmap'))
            : const [],
        zones: [
          if (gs == null && applyFilters && on('FloodRisk')) ...NerGeo.floodZones,
          if (gs == null && applyFilters && on('Landslide')) ...NerGeo.landslideZones,
        ],
        pois: applyFilters && on('Infrastructure') ? NerGeo.infrastructure : const [],
        // Demo fleet + every live rider from the mobile app (Supabase Realtime).
        vehicles: on('Logistics')
            ? [
                ...NerGeo.vehicles(demoOnly(_kFleet)),
                ...liveRiderVehicles(ref.watch(liveRidersProvider).valueOrNull),
              ]
            : const [],
        incidents: [
          if (showIncidents && on('Incidents'))
            for (final inc in demoOnly(_kIncidents))
              if (!applyFilters || inc.severity.index <= _riskFloor.index)
                MapIncident(
                  id: inc.id,
                  point: NerGeo.locate(inc.location, inc.route),
                  severity: inc.severity,
                  type: inc.type,
                  label: '${inc.id} · ${inc.typeLabel} · ${inc.location}',
                  resolved: inc.statusLabel == 'Resolved',
                ),
        ],
      ),
    );
  }

  /// Static location preview centred on one incident.
  Widget _incidentMap(int i, double height) {
    final inc = demoOnly(_kIncidents)[i];
    final point = NerGeo.locate(inc.location, inc.route);
    final line = NerGeo.highway(inc.route);
    return SizedBox(
      height: height,
      child: NerMap(
        interactive: false,
        fitPoints: [point],
        maxFitZoom: 9,
        routes: [
          if (line != null)
            MapRoute(label: NerGeo.routeIdOf(inc.route), points: line, tone: _mapTone(inc.route)),
        ],
        zones: [
          MapZone(center: point, radiusMeters: 6000, kind: MapZoneKind.impact, label: inc.typeLabel),
        ],
        incidents: [
          MapIncident(
            id: inc.id,
            point: point,
            severity: inc.severity,
            type: inc.type,
            label: '${inc.id} · ${inc.typeLabel}',
            resolved: inc.statusLabel == 'Resolved',
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c, double s) => Container(
    width: s, height: s,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
  );

  Widget _buildBody() {
    switch (_nav) {
      case ControlNav.command:    return _buildCommand();
      case ControlNav.map:        return _buildMap();
      case ControlNav.logistics:  return _buildLogistics();
      case ControlNav.riders:     return const LiveRidersScreen(embedded: true);
      case ControlNav.incidents:  return _buildIncidents();
      case ControlNav.routes:     return _buildRoutes();
      case ControlNav.ai:         return _buildAI();
      case ControlNav.alerts:     return _buildAlerts();
      case ControlNav.analytics:  return _buildAnalytics();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 1. COMMAND CENTER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCommand() {
    if (!DemoMode.enabled) {
      return DemoOffPage(
        title: "What's happening across NER",
        subtitle: 'Command center',
        live: [
          SectionTitle(title: 'Highest-risk segments today'),
          const MlTopAlertsCard(canPromote: true, limit: 3),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("What's happening across NER", style: const TextStyle(fontFamily: 'PublicSans', fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navy900)),
                  const SizedBox(height: 2),
                  Text('Live regional dashboard · pulling from 8 states, 62 vehicles, 142 sensors', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: _refreshing
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.hairline)),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy900)),
                          const SizedBox(width: 8),
                          Text('Refreshing…', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900)),
                        ],
                      ),
                    )
                  : _refreshed
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: AppColors.clearBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.deepGreen700.withValues(alpha: 0.3))),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 14, color: AppColors.deepGreen700),
                            const SizedBox(width: 6),
                            Text('Updated just now', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.deepGreen700)),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: _doRefresh,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy900,
                          side: const BorderSide(color: AppColors.hairline),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.refresh_outlined, size: 16),
                        label: Text('Refresh', style: AppTextStyles.buttonSmall),
                      ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: 160,
              child: [
                KpiTile(label: 'Active incidents', value: '27', tone: KpiTone.navy, hint: '8 states reporting'),
                KpiTile(label: 'Critical', value: '06', tone: KpiTone.critical, hint: 'Requires immediate action'),
                KpiTile(label: 'Affected routes', value: '14', tone: KpiTone.saffron, hint: 'Of 42 monitored'),
                KpiTile(label: 'At-risk logistics', value: '18', tone: KpiTone.saffron, hint: '54 total convoys'),
                KpiTile(label: 'Districts on alert', value: '04', tone: KpiTone.critical, hint: '26 districts total'),
                KpiTile(label: 'Regional access.', value: '68/100', tone: KpiTone.saffron, hint: 'Restricted band'),
              ][i],
            ),
          ),
        ),
        SectionTitle(
          title: 'Regional situation map',
          action: TextButton(
            onPressed: () => setState(() => _mapExpanded = true),
            child: Text('Expand', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900)),
          ),
        ),
        CardSurface(
          padding: EdgeInsets.zero,
          onTap: () => setState(() => _mapExpanded = true),
          child: Column(
            children: [
              _regionalMap(height: 160),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text('8 states · 6 critical incidents · 18 vehicles in motion', style: AppTextStyles.caption),
                    const Spacer(),
                    Text('tap to expand', style: AppTextStyles.caption.copyWith(color: AppColors.navy900)),
                    const Icon(Icons.chevron_right, size: 14, color: AppColors.slate500),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle(
          title: 'Critical situation',
          action: TextButton(
            onPressed: () => _go(ControlNav.incidents),
            child: Text('View all', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900)),
          ),
        ),
        ...List.generate(3, (i) {
          final data = [
            (id: 'INC-4471', title: 'Flood · Brahmaputra overflow', priority: Priority.critical, location: 'Barpeta, Assam · NH-27', details: 'Affects 42 km · 8 villages · 3 convoys halted', time: '34 min ago'),
            (id: 'INC-4460', title: 'Landslide · Tawang Pass', priority: Priority.critical, location: 'Tawang, Arunachal · NH-13', details: '2 vehicles stranded · slide zone 18 km', time: '1h 12m ago'),
            (id: 'INC-4455', title: 'Logistics block · Dimapur yard', priority: Priority.high, location: 'Dimapur, Nagaland · NH-2', details: 'Receiving bay full · 11 trucks waiting', time: '1h 48m ago'),
          ][i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
            child: CardSurface(
              leftAccentColor: _leftAccent(data.priority),
              onTap: () => _openIncidentSheet(i),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(data.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500)),
                      const Spacer(),
                      PriorityBadge(level: data.priority),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(data.title, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 4),
                  Row(children: [Icon(Icons.location_on_outlined, size: 12, color: AppColors.slate500), const SizedBox(width: 4), Expanded(child: Text(data.location, style: AppTextStyles.caption))]),
                  const SizedBox(height: 4),
                  Text(data.details, style: AppTextStyles.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.av_timer_outlined, size: 13, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Text(data.time, style: AppTextStyles.meta),
                      const Spacer(),
                      SizedBox(
                        height: 30,
                        child: TextButton(
                          onPressed: () => _openIncidentSheet(i),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), foregroundColor: AppColors.navy900),
                          child: Text('View', style: AppTextStyles.buttonSmall),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        SectionTitle(
          title: 'Regional risk intelligence',
          action: TextButton(onPressed: () {}, child: Text('Details', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900))),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final d = [
                (label: 'Overall risk', score: 78, riskLevel: 'Critical', isUp: true),
                (label: 'Flood', score: 82, riskLevel: 'High', isUp: true),
                (label: 'Landslide', score: 71, riskLevel: 'High', isUp: false),
                (label: 'Route', score: 76, riskLevel: 'Critical', isUp: true),
                (label: 'Logistics', score: 68, riskLevel: 'High', isUp: false),
              ][i];
              final tone = d.riskLevel == 'Critical' ? KpiTone.critical : d.riskLevel == 'High' ? KpiTone.saffron : KpiTone.navy;
              final valColor = d.riskLevel == 'Critical' ? AppColors.signalRed700 : d.riskLevel == 'High' ? AppColors.saffron600 : AppColors.navy900;
              return SizedBox(
                width: 150,
                child: CardSurface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.label, style: AppTextStyles.caption.copyWith(color: AppColors.slate500)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('${d.score}', style: AppTextStyles.kpiValue.copyWith(fontSize: 22, color: valColor)),
                          const SizedBox(width: 6),
                          const Spacer(),
                          Icon(d.isUp ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: d.isUp ? AppColors.signalRed700 : AppColors.deepGreen700),
                          Text(d.isUp ? '↑' : '↓', style: AppTextStyles.caption.copyWith(color: d.isUp ? AppColors.signalRed700 : AppColors.deepGreen700, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tone == KpiTone.critical ? AppColors.criticalBg : tone == KpiTone.saffron ? AppColors.saffronBg : AppColors.navyTint,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(d.riskLevel, style: AppTextStyles.chipLabel.copyWith(color: valColor)),
                      ),
                      const SizedBox(height: 8),
                      AccessScoreBar(score: d.score, compact: true),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SectionTitle(
          title: 'District situation',
          action: TextButton(onPressed: () {}, child: Text('All districts', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900))),
        ),
        ...List.generate(3, (i) {
          final d = demoOnly(_kDistricts)[i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
            child: CardSurface(
              leftAccentColor: _leftAccent(d.risk),
              onTap: () {},
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${d.name}, ${d.state}', style: AppTextStyles.cardTitle)),
                      PriorityBadge(level: d.risk),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AccessScoreBar(score: d.accessScore),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _miniBadge('${d.incidentCount} incidents', AppColors.navy900, AppColors.navyTint),
                      const SizedBox(width: 6),
                      _miniBadge('${d.criticalCount} critical', AppColors.signalRed700, AppColors.criticalBg),
                      const SizedBox(width: 6),
                      _miniBadge('${d.blockedRoutes} routes', AppColors.saffronDark, AppColors.saffronBg),
                      const Spacer(),
                      StatusChip(tone: ChipTone.muted, label: d.statusLabel),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(d.logisticsNote, style: AppTextStyles.bodySmall)),
                      const Icon(Icons.chevron_right, color: AppColors.slate500, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        SectionTitle(
          title: 'Live logistics',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.systemOnline, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('LIVE', style: AppTextStyles.eyebrow.copyWith(color: AppColors.deepGreen700)),
            ],
          ),
        ),
        Text('Last updated 10 sec ago', style: AppTextStyles.caption),
        const SizedBox(height: 10),
        ...List.generate(3, (i) {
          final f = demoOnly(_kFleet)[i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 2 ? 12 : 10),
            child: _fleetCard(f),
          );
        }),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton(
            onPressed: () => _go(ControlNav.logistics),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.hairline), foregroundColor: AppColors.navy900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('View All Logistics', style: AppTextStyles.buttonSmall),
          ),
        ),
        SectionTitle(
          title: 'Road disruption risk',
          action: TextButton(onPressed: () => _go(ControlNav.ai), child: Text('All', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900))),
        ),
        const MlTopAlertsCard(canPromote: true, limit: 3),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton(
            onPressed: () => _go(ControlNav.ai),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.hairline), foregroundColor: AppColors.navy900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('View All Predictions', style: AppTextStyles.buttonSmall),
          ),
        ),
        SectionTitle(title: 'Priority actions'),
        ...List.generate(5, (i) {
          final d = [
            (priority: Priority.critical, action: 'Deploy rescue team to Barpeta NH-27 flooded zone', location: 'Barpeta, Assam', due: 'Due 18 min'),
            (priority: Priority.critical, action: 'Halt all northbound NH-13 convoys before slide zone', location: 'Tawang, Arunachal', due: 'Due 24 min'),
            (priority: Priority.high, action: 'Redirect 2 convoys from Silchar to Karimganj yard', location: 'Silchar, Assam', due: 'Due 1h 12m'),
            (priority: Priority.high, action: 'Schedule mandatory rest stop for TRK-2091 driver', location: 'NH-306 en route', due: 'Due 40 min'),
            (priority: Priority.medium, action: 'Verify INC-4432 Jorabat weather cleared', location: 'Jorabat, Assam', due: 'Due 2h 00m'),
          ][i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 4 ? 0 : 8),
            child: CardSurface(
              leftAccentColor: _leftAccent(d.priority),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.action, style: AppTextStyles.cardTitle),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 12, color: AppColors.slate500),
                            const SizedBox(width: 3),
                            Expanded(child: Text(d.location, style: AppTextStyles.caption)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.av_timer_outlined, size: 12, color: AppColors.slate500),
                            const SizedBox(width: 3),
                            Text(d.due, style: AppTextStyles.meta),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: FilledButton.tonal(
                      onPressed: () {},
                      style: FilledButton.styleFrom(backgroundColor: AppColors.navyTint, foregroundColor: AppColors.navy900),
                      child: Text('Review', style: AppTextStyles.buttonSmall),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        SectionTitle(
          title: 'Alert summary',
          action: TextButton(onPressed: () => _go(ControlNav.alerts), child: Text('View alerts', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900))),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            StatusChip(tone: ChipTone.critical, label: 'Critical 06'),
            StatusChip(tone: ChipTone.saffron, label: 'High 11'),
            StatusChip(tone: ChipTone.navy, label: 'Moderate 18'),
            StatusChip(tone: ChipTone.muted, label: 'Info 24'),
          ],
        ),
        SectionTitle(title: 'Regional accessibility'),
        CardSurface(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AccessScoreBar(score: 68),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _statCol('Fully accessible', '62%', ChipTone.clear),
                  ),
                  Expanded(
                    child: _statCol('Partially', '24%', ChipTone.saffron),
                  ),
                  Expanded(
                    child: _statCol('Restricted', '14%', ChipTone.critical),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(title: 'Quick actions'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.8,
          children: [
            _qaBtn(Icons.warning_outlined, 'View Critical Incidents', AppColors.signalRed700, AppColors.criticalBg, () => _go(ControlNav.incidents)),
            _qaBtn(Icons.map_outlined, 'Regional Map', AppColors.navy900, AppColors.navyTint, () => _go(ControlNav.map)),
            _qaBtn(Icons.local_shipping_outlined, 'Live Logistics', AppColors.deepGreen700, AppColors.clearBg, () => _go(ControlNav.logistics)),
            _qaBtn(Icons.insights_outlined, 'Risk Intelligence', AppColors.saffron600, AppColors.saffronBg, () => _go(ControlNav.analytics)),
            _qaBtn(Icons.auto_awesome_outlined, 'AI Predictions', AppColors.navy900, AppColors.navyTint, () => _go(ControlNav.ai)),
            _qaBtn(Icons.picture_as_pdf_outlined, 'Generate Report', AppColors.navy900, AppColors.navyTint, () {}),
          ],
        ),
      ],
    );
  }

  Widget _miniBadge(String text, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: AppTextStyles.chipLabel.copyWith(fontSize: 11, color: fg)),
  );

  Widget _statCol(String label, String value, ChipTone tone) {
    final fg = tone == ChipTone.clear ? AppColors.deepGreen700 : tone == ChipTone.saffron ? AppColors.saffron600 : AppColors.signalRed700;
    return Column(
      children: [
        Text(value, style: AppTextStyles.statValue.copyWith(color: fg)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _qaBtn(IconData ic, String label, Color fg, Color bg, VoidCallback onTap) => CardSurface(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(ic, size: 18, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTextStyles.cardTitle.copyWith(fontSize: 13))),
        ],
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // 2. MAP
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Regional Map', style: AppTextStyles.pageHeading),
                  const SizedBox(height: 2),
                  Text('NER 8-state corridor monitor · route risk, incident overlays, fleet positions', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: FilledButton.tonal(
                onPressed: () => setState(() => _simSheetOpen = true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.saffronBg, foregroundColor: AppColors.saffronDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text('Simulate Route Closure', style: AppTextStyles.buttonSmall),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CardSurface(
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _filtersOpen = !_filtersOpen),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text('Filters', style: AppTextStyles.cardTitle),
                      const Spacer(),
                      Text('Layers · Risk · Time', style: AppTextStyles.caption),
                      Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.slate500),
                    ],
                  ),
                ),
              ),
              if (_filtersOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LAYERS', style: AppTextStyles.eyebrow.copyWith(color: AppColors.slate500)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _layers.entries.map((e) => _filterChip(e.key, e.value, () => setState(() => _layers[e.key] = !e.value))).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text('RISK LEVEL', style: AppTextStyles.eyebrow.copyWith(color: AppColors.slate500)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ['Low', 'Moderate', 'High', 'Critical'].map((r) => _pillChip(r, _riskLevel == r, () => setState(() => _riskLevel = r))).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text('TIME RANGE', style: AppTextStyles.eyebrow.copyWith(color: AppColors.slate500)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ['Now', '+6h', '+24h', '+72h'].map((t) => _pillChip(t, _timeRange == t, () => setState(() => _timeRange = t))).toList(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_simulating && _simulatedRoute != null) ...[
          const SizedBox(height: 16),
          AiCard(
            kind: 'Simulation result · OSRM',
            title: 'Simulated closure of $_simulatedRoute',
            body: ClosureImpactView(query: _closureQuery!),
          ),
        ],
        const SizedBox(height: 16),
        Stack(
          children: [
            CardSurface(
              padding: EdgeInsets.zero,
              child: _regionalMap(
                height: 300,
                interactive: true,
                applyFilters: true,
                onExpand: () => setState(() => _mapExpanded = true),
              ),
            ),
            const Positioned(left: 12, bottom: 12, child: MapLegend()),
          ],
        ),
        const SizedBox(height: 16),
        SectionTitle(title: 'Route Status'),
        ...List.generate(7, (i) {
          final r = demoOnly(_kRoutes)[i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 6 ? 0 : 10),
            child: CardSurface(
              leftAccentColor: r.status == RouteStatus.blocked || r.status == RouteStatus.closed ? AppColors.signalRed700 : r.status == RouteStatus.restricted ? AppColors.saffron600 : Colors.transparent,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text(r.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.navy900, fontSize: 10)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.id} · ${r.name}', style: AppTextStyles.cardTitle),
                        const SizedBox(height: 2),
                        Text('${r.distance} · ${r.weather}', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  StatusChip(tone: _routeTone(r.status), label: r.status.name.toUpperCase()),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _filterChip(String label, bool on, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? AppColors.navyTint : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: on ? AppColors.navy900.withValues(alpha: 0.4) : AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14, height: 14,
            child: Checkbox(
              activeColor: AppColors.navy900,
              value: on,
              onChanged: (_) => onTap(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: AppColors.hairline, width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.chipLabel),
        ],
      ),
    ),
  );

  Widget _pillChip(String label, bool on, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on ? AppColors.navy900 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.navy900 : AppColors.hairline),
      ),
      child: Text(label, style: AppTextStyles.chipLabel.copyWith(color: on ? Colors.white : AppColors.slate500)),
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // 3. LOGISTICS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLogistics() {
    if (!DemoMode.enabled) {
      return const DemoOffPage(
        title: 'Live Logistics',
        subtitle: 'Fleet positions, route adherence, at-risk shipments, and delays across the NER corridor.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.clearBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: AppColors.deepGreen700.withValues(alpha: 0.3))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.systemOnline, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('LIVE', style: AppTextStyles.eyebrow.copyWith(color: AppColors.deepGreen700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const DemoTag(),
          ],
        ),
        const SizedBox(height: 10),
        Text('Live Logistics', style: AppTextStyles.pageHeading),
        const SizedBox(height: 2),
        Text('Fleet positions, route adherence, at-risk shipments, and delays across the NER corridor.', style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: const [
            KpiTile(label: 'Active convoys', value: '54', tone: KpiTone.navy, hint: 'Of 62 fleet total'),
            KpiTile(label: 'Delayed', value: '11', tone: KpiTone.saffron, hint: 'ETA +1h or more'),
            KpiTile(label: 'At risk', value: '08', tone: KpiTone.critical, hint: 'Route + weather signal'),
            KpiTile(label: 'Stopped / held', value: '03', tone: KpiTone.critical, hint: 'Awaiting clearance'),
          ],
        ),
        SectionTitle(title: 'Active Convoys'),
        CardSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _regionalMap(height: 150, showIncidents: false),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    _dot(AppColors.gold, 8),
                    const SizedBox(width: 5),
                    Text('18 vehicles in motion', style: AppTextStyles.caption),
                    const Spacer(),
                    const MapLegend(),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle(title: 'At-Risk Convoys'),
        ...List.generate(3, (i) {
          final f = [demoOnly(_kFleet)[1], demoOnly(_kFleet)[3], demoOnly(_kFleet)[4]][i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
            child: CardSurface(
              leftAccentColor: _leftAccent(f.risk),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: f.risk == Priority.critical ? AppColors.criticalBg : AppColors.saffronBg, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text(f.id.substring(4), style: AppTextStyles.eyebrowMd.copyWith(color: f.risk == Priority.critical ? AppColors.signalRed700 : AppColors.saffronDark)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500)),
                        const SizedBox(height: 2),
                        Text(f.route, style: AppTextStyles.cardTitle),
                        const SizedBox(height: 2),
                        Text('→ ${f.destination}', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(tone: f.risk == Priority.critical ? ChipTone.critical : ChipTone.saffron, label: f.statusLabel),
                      const SizedBox(height: 6),
                      Text(f.eta, style: AppTextStyles.meta),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        SectionTitle(title: 'All Shipments'),
        ...List.generate(6, (i) {
          final s = [
            (id: 'SHP-2104', cargo: 'Medical supplies · 8 pallets', pri: Priority.high, status: ShipmentStatus.delayed, origin: 'Guwahati Hub', dest: 'Silchar Depot', loc: 'NH-27 · Barpeta', route: 'NH-27', eta: 'ETA +2h 40m', delay: '+2h 40m', delayTone: ChipTone.critical),
            (id: 'SHP-2098', cargo: 'Rice bags · 14 MT', pri: Priority.medium, status: ShipmentStatus.inTransit, origin: 'Jorabat Yard', dest: 'Shillong Depot', loc: 'NH-6 · Umsning', route: 'NH-6', eta: 'ETA 2h 15m', delay: 'On time', delayTone: ChipTone.clear),
            (id: 'SHP-2091', cargo: 'Construction steel', pri: Priority.critical, status: ShipmentStatus.delayed, origin: 'Dimapur', dest: 'Kohima Depot', loc: 'NH-2 · Chümoukedima', route: 'NH-2', eta: 'Hold', delay: '+3h 10m', delayTone: ChipTone.critical),
            (id: 'SHP-2088', cargo: 'PPE kits · 5 cartons', pri: Priority.low, status: ShipmentStatus.onSchedule, origin: 'Guwahati Hub', dest: 'Tawang Base', loc: 'NH-13 · Bomdila', route: 'NH-13', eta: 'ETA 5h 30m', delay: 'On time', delayTone: ChipTone.clear),
            (id: 'SHP-2082', cargo: 'Fruits & vegetables', pri: Priority.medium, status: ShipmentStatus.inTransit, origin: 'Siliguri Hub', dest: 'Guwahati Hub', loc: 'NH-27 · Kokrajhar', route: 'NH-27', eta: 'ETA 4h 00m', delay: '+30m', delayTone: ChipTone.saffron),
            (id: 'SHP-2076', cargo: 'Fuel drums · 200L ×12', pri: Priority.high, status: ShipmentStatus.delayed, origin: 'Bongaigaon', dest: 'Tezpur Depot', loc: 'NH-15 · Dhekiajuli', route: 'NH-15', eta: 'ETA +1h 20m', delay: '+1h 20m', delayTone: ChipTone.critical),
          ][i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 5 ? 0 : 10),
            child: CardSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(s.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500)),
                      const Spacer(),
                      PriorityBadge(level: s.pri),
                      const SizedBox(width: 6),
                      StatusChip(tone: s.status == ShipmentStatus.onSchedule ? ChipTone.clear : s.status == ShipmentStatus.delayed ? ChipTone.critical : ChipTone.navy, label: s.status.name.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}').trim()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(s.cargo, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.arrow_upward, size: 12, color: AppColors.deepGreen700),
                      const SizedBox(width: 4),
                      Expanded(child: Text('${s.origin} → ${s.dest}', style: AppTextStyles.caption)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 12, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Expanded(child: Text('${s.loc} · via ${s.route}', style: AppTextStyles.caption)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(s.eta, style: AppTextStyles.bodySmallMedium),
                      const Spacer(),
                      Text(s.delay, style: AppTextStyles.bodySmall.copyWith(
                        color: s.delayTone == ChipTone.clear ? AppColors.deepGreen700 : s.delayTone == ChipTone.saffron ? AppColors.saffron600 : AppColors.signalRed700,
                        fontWeight: FontWeight.w600,
                      )),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _fleetCard(FleetVehicle f) {
    final tone = f.risk == Priority.critical ? ChipTone.critical : f.risk == Priority.high ? ChipTone.saffron : f.risk == Priority.medium ? ChipTone.navy : ChipTone.clear;
    return CardSurface(
      leftAccentColor: _leftAccent(f.risk),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(f.id.substring(4), style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.navy900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500)),
                const SizedBox(height: 2),
                Text(f.route, style: AppTextStyles.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text('→ ${f.destination}', style: AppTextStyles.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(tone: tone, label: f.statusLabel),
              const SizedBox(height: 4),
              PriorityBadge(level: f.risk),
              const SizedBox(height: 4),
              Text(f.eta, style: AppTextStyles.meta),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 4. INCIDENTS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildIncidents() {
    final tabCounts = {
      IncTab.all: demoOnly(_kIncidents).length,
      IncTab.pending: demoOnly(_kIncidents).where((e) => e.statusLabel == 'Pending').length,
      IncTab.active: demoOnly(_kIncidents).where((e) => e.statusLabel == 'Active').length,
      IncTab.escalated: demoOnly(_kIncidents).where((e) => e.statusLabel == 'Escalated').length,
      IncTab.resolved: demoOnly(_kIncidents).where((e) => e.statusLabel == 'Resolved').length,
    };
    final filtered = _incTab == IncTab.all ? demoOnly(_kIncidents) : demoOnly(_kIncidents).where((e) {
      final m = {IncTab.pending: 'Pending', IncTab.active: 'Active', IncTab.escalated: 'Escalated', IncTab.resolved: 'Resolved'};
      return e.statusLabel == m[_incTab];
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Incidents', style: AppTextStyles.pageHeading),
        const SizedBox(height: 2),
        Text('All reported incidents across the NER corridor — verify, assign, escalate, resolve.', style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        ScrollTabs<IncTab>(
          tabs: IncTab.values.map((t) => ScrollTab<IncTab>(id: t, label: t.name[0].toUpperCase() + t.name.substring(1), count: tabCounts[t])).toList(),
          active: _incTab,
          onChange: (v) => setState(() => _incTab = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _filterSelect('Severity', _severityFilter ?? 'All', ['All', 'Critical', 'High', 'Medium', 'Low'], (v) => setState(() => _severityFilter = v)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _filterSelect('Type', _typeFilter ?? 'All', ['All', 'Flood', 'Landslide', 'Accident', 'Infra', 'Other'], (v) => setState(() => _typeFilter = v)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...List.generate(filtered.length, (i) {
          final inc = filtered[i];
          final idx = demoOnly(_kIncidents).indexOf(inc);
          final expanded = _detailIncident == idx;
          return Padding(
            padding: EdgeInsets.only(bottom: i == filtered.length - 1 ? 0 : 12),
            child: expanded ? _incidentDetail(idx) : _incidentCard(idx),
          );
        }),
      ],
    );
  }

  Widget _filterSelect(String label, String value, List<String> opts, ValueChanged<String> onCh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.hairline), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: AppTextStyles.eyebrow.copyWith(color: AppColors.slate500)),
          const SizedBox(height: 2),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              style: AppTextStyles.cardTitle.copyWith(fontSize: 14),
              items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o, style: AppTextStyles.cardTitle.copyWith(fontSize: 14)))).toList(),
              onChanged: (v) { if (v != null) onCh(v); },
            ),
          ),
        ],
      ),
    );
  }

  Widget _incidentCard(int i) {
    final inc = demoOnly(_kIncidents)[i];
    return CardSurface(
      leftAccentColor: _leftAccent(inc.severity),
      onTap: () => setState(() => _detailIncident = i),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: inc.severity == Priority.critical ? AppColors.criticalBg : inc.severity == Priority.high ? AppColors.saffronBg : AppColors.navyTint, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text(inc.id.substring(7), style: AppTextStyles.eyebrowMd.copyWith(color: inc.severity == Priority.critical ? AppColors.signalRed700 : inc.severity == Priority.high ? AppColors.saffronDark : AppColors.navy900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${inc.id} · ${inc.typeLabel}', style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500)),
                    const SizedBox(height: 2),
                    Text(inc.typeLabel, style: AppTextStyles.cardTitle),
                  ],
                ),
              ),
              PriorityBadge(level: inc.severity),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [Icon(Icons.location_on_outlined, size: 12, color: AppColors.slate500), const SizedBox(width: 4), Expanded(child: Text('${inc.location} · ${inc.route}', style: AppTextStyles.caption))]),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.person_outline, size: 12, color: AppColors.slate500),
              const SizedBox(width: 4),
              Text('Reported by ${inc.reporter} · ${inc.time}', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(inc.verified ? Icons.check_circle_outline : Icons.pending_outlined, size: 13, color: inc.statusLabel == 'Resolved' ? AppColors.deepGreen700 : AppColors.slate500),
                    const SizedBox(width: 4),
                    Text('${inc.verified ? 'Verified' : 'Unverified'} · ${inc.assignedOfficer == 'Unassigned' ? 'Unassigned' : 'Assigned: ${inc.assignedOfficer}'}', style: AppTextStyles.meta),
                  ],
                ),
              ),
              StatusChip(tone: inc.statusLabel == 'Resolved' ? ChipTone.clear : inc.statusLabel == 'Escalated' ? ChipTone.critical : inc.statusLabel == 'Active' ? ChipTone.saffron : ChipTone.navy, label: inc.statusLabel),
              const SizedBox(width: 6),
              SizedBox(
                height: 30,
                child: TextButton(
                  onPressed: () => setState(() => _detailIncident = i),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), foregroundColor: AppColors.navy900),
                  child: Text('View', style: AppTextStyles.buttonSmall),
                ),
              ),
              if (!inc.verified)
                SizedBox(
                  height: 30,
                  child: FilledButton.tonal(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: AppColors.navyTint, foregroundColor: AppColors.navy900),
                    child: Text('Verify', style: AppTextStyles.buttonSmall),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _incidentDetail(int i) {
    final inc = demoOnly(_kIncidents)[i];
    return CardSurface(
      leftAccentColor: _leftAccent(inc.severity),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                SizedBox(
                  height: 30,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _detailIncident = null),
                    style: TextButton.styleFrom(foregroundColor: AppColors.navy900, padding: const EdgeInsets.symmetric(horizontal: 4)),
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text('Back', style: AppTextStyles.buttonSmall),
                  ),
                ),
                const Spacer(),
                PriorityBadge(level: inc.severity),
                const SizedBox(width: 6),
                StatusChip(tone: inc.statusLabel == 'Resolved' ? ChipTone.clear : inc.statusLabel == 'Escalated' ? ChipTone.critical : inc.statusLabel == 'Active' ? ChipTone.saffron : ChipTone.navy, label: inc.statusLabel),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${inc.id} · ${inc.typeLabel}', style: AppTextStyles.cardTitle.copyWith(fontSize: 17)),
                const SizedBox(height: 4),
                Text('${inc.location} · on ${inc.route}', style: AppTextStyles.bodySmall),
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(6), child: _incidentMap(i, 140)),
                const SizedBox(height: 14),
                _detailRow('Reported by', inc.reporter),
                _detailRow('Reported', inc.time),
                _detailRow('Assigned to', inc.assignedOfficer == 'Unassigned' ? 'Unassigned' : inc.assignedOfficer),
                _detailRow('Status', inc.statusLabel),
                _detailRow('Severity', _pLabel(inc.severity)),
                _detailRow('Route', inc.route),
                const SizedBox(height: 10),
                AiCard(
                  demo: true, kind: 'Demo estimate',
                  confidence: 82,
                  title: 'Risk estimate for this incident',
                  body: const AiCardText('Current trajectory suggests 78% probability of route impact extending >12 hrs. Recommended escalation to State Control Room and pre-notification of 3 reroute plans.'),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: [
                    _actBtn(Icons.verified_user_outlined, 'Verify', AppColors.navy900, AppColors.navyTint, () {}),
                    _actBtn(Icons.assignment_ind_outlined, 'Reassign', AppColors.navy900, AppColors.navyTint, () {}),
                    _actBtn(Icons.trending_up_outlined, 'Escalate', AppColors.signalRed700, AppColors.criticalBg, () {}),
                    _actBtn(Icons.check_circle_outline, 'Mark Resolved', AppColors.deepGreen700, AppColors.clearBg, () {}),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pLabel(Priority p) => switch (p) {
    Priority.critical => 'Critical',
    Priority.high => 'High',
    Priority.medium => 'Medium',
    Priority.low => 'Low',
  };

  Widget _detailRow(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text(k, style: AppTextStyles.caption.copyWith(color: AppColors.slate500))),
        Expanded(child: Text(v, style: AppTextStyles.bodySmallMedium)),
      ],
    ),
  );

  Widget _actBtn(IconData ic, String label, Color fg, Color bg, VoidCallback onTap) => CardSurface(
    onTap: onTap,
    backgroundColor: bg,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Row(
      children: [
        Icon(ic, size: 15, color: fg),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: AppTextStyles.buttonSmall.copyWith(color: fg))),
      ],
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // 5. ROUTES
  // ═══════════════════════════════════════════════════════════════
  Widget _buildRoutes() {
    if (!DemoMode.enabled) {
      return const DemoOffPage(
        title: 'Routes',
        subtitle: 'National Highways across NER corridor · live access, conditions, and ETA impact.',
      );
    }
    final tabCounts = {
      RouteTab.all: demoOnly(_kRoutes).length,
      RouteTab.open: demoOnly(_kRoutes).where((e) => e.status == RouteStatus.open).length,
      RouteTab.restricted: demoOnly(_kRoutes).where((e) => e.status == RouteStatus.restricted).length,
      RouteTab.blocked: demoOnly(_kRoutes).where((e) => e.status == RouteStatus.blocked).length,
      RouteTab.closed: demoOnly(_kRoutes).where((e) => e.status == RouteStatus.closed).length,
    };
    final filtered = _routeTab == RouteTab.all ? demoOnly(_kRoutes) : demoOnly(_kRoutes).where((e) {
      final m = {RouteTab.open: RouteStatus.open, RouteTab.restricted: RouteStatus.restricted, RouteTab.blocked: RouteStatus.blocked, RouteTab.closed: RouteStatus.closed};
      return e.status == m[_routeTab];
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Routes', style: AppTextStyles.pageHeading),
        const SizedBox(height: 2),
        Text('National Highways across NER corridor · live access, conditions, and ETA impact.', style: AppTextStyles.bodySmall),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            const KpiTile(label: 'Routes total', value: '14', tone: KpiTone.navy, hint: 'NER monitored NH'),
            KpiTile(label: 'Blocked', value: '${tabCounts[RouteTab.blocked]}', tone: KpiTone.critical, hint: 'Closed to all traffic'),
            KpiTile(label: 'Restricted', value: '${tabCounts[RouteTab.restricted]}', tone: KpiTone.saffron, hint: '1-lane or speed limit'),
            KpiTile(label: 'Open', value: '${tabCounts[RouteTab.open]}', tone: KpiTone.clear, hint: 'Full 2-lane access'),
          ],
        ),
        const SizedBox(height: 16),
        ScrollTabs<RouteTab>(
          tabs: RouteTab.values.map((t) => ScrollTab<RouteTab>(id: t, label: t.name[0].toUpperCase() + t.name.substring(1), count: tabCounts[t])).toList(),
          active: _routeTab,
          onChange: (v) => setState(() => _routeTab = v),
        ),
        const SizedBox(height: 16),
        ...List.generate(filtered.length, (i) {
          final r = filtered[i];
          final delayColor = r.status == RouteStatus.open ? AppColors.deepGreen700 : r.status == RouteStatus.restricted ? AppColors.saffron600 : AppColors.signalRed700;
          return Padding(
            padding: EdgeInsets.only(bottom: i == filtered.length - 1 ? 0 : 10),
            child: CardSurface(
              leftAccentColor: r.status == RouteStatus.blocked || r.status == RouteStatus.closed ? AppColors.signalRed700 : r.status == RouteStatus.restricted ? AppColors.saffron600 : Colors.transparent,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: Text(r.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.navy900, fontSize: 10)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r.id} · ${r.name}', style: AppTextStyles.cardTitle),
                            const SizedBox(height: 2),
                            Text(r.distance, style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                      StatusChip(tone: _routeTone(r.status), label: r.status.name.toUpperCase()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AccessScoreBar(score: r.score),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.wb_sunny_outlined, size: 13, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Text(r.weather, style: AppTextStyles.caption),
                      const SizedBox(width: 14),
                      Icon(Icons.av_timer_outlined, size: 13, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Text(r.eta, style: AppTextStyles.caption),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(r.delay, style: AppTextStyles.caption.copyWith(color: delayColor, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Updated ${r.updated}', style: AppTextStyles.meta),
                      const Spacer(),
                      SizedBox(
                        height: 30,
                        child: TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), foregroundColor: AppColors.navy900),
                          child: Text('View details', style: AppTextStyles.buttonSmall),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 6. AI PREDICTIONS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildAI() {
    if (!DemoMode.enabled) {
      return DemoOffPage(
        title: 'AI Predictions',
        subtitle: 'Road disruption risk from the NER model.',
        live: [
          SectionTitle(title: 'Highest-risk segments today'),
          const MlTopAlertsCard(canPromote: true),
          SectionTitle(title: 'Risk on planned routes'),
          const MlRoutesBoard(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Predictions', style: AppTextStyles.pageHeading),
        const SizedBox(height: 2),
        Text('Road disruption risk from the NER model, followed by illustrative scenarios.', style: AppTextStyles.bodySmall),
        SectionTitle(title: 'Highest-risk segments today'),
        const MlTopAlertsCard(canPromote: true),
        SectionTitle(title: 'Risk on planned routes'),
        const MlRoutesBoard(),
        SectionTitle(title: 'Illustrative scenarios (demo data)', action: const DemoTag()),
        AiCard(demo: true, kind: 'Demo scenario', confidence: 87, title: 'Flood · Dimapur-Nagaland corridor (NH-29)', body: const AiCardText('72hr cumulative rainfall 212 mm projected. Basins near saturation. 5 km of NH-29 south of Dimapur at risk of submersion Day 2 morning.')),
        const SizedBox(height: 12),
        AiCard(demo: true, kind: 'Demo scenario', confidence: 78, title: 'Route disruption · NH-27 Barpeta stretch', body: const AiCardText('Flood + congestion compound signal. 78% chance current NH-27 closure extends beyond 18 hrs. Pre-diversion of 6 convoys recommended.')),
        const SizedBox(height: 12),
        AiCard(demo: true, kind: 'Demo scenario', confidence: 81, title: 'Logistics delay · Silchar cluster (NH-306)', body: const AiCardText('Yard capacity 138% + route restriction. ETA impact +3.5h across 14 inbound shipments. Reroute 50% to Karimganj yard advised.')),
        const SizedBox(height: 12),
        AiCard(demo: true, kind: 'Demo scenario', confidence: 74, title: 'Landslide · Tawang Pass (NH-13)', body: const AiCardText('Seismic + rainfall + soil moisture model. 74% probability of slide event in Zone-B (16-22 km from Tawang) within 8 hrs window.')),
        const SizedBox(height: 12),
        AiCard(demo: true, kind: 'Demo scenario', confidence: 72, title: 'Risk escalation · Regional composite', body: const AiCardText('Composite regional risk index trending up. If current signals persist for 6 hrs, regional state moves to CRITICAL band. Recommend pre-alert to State Control Rooms.')),
        SectionTitle(title: 'Prediction factors'),
        ...List.generate(3, (i) {
          final d = [
            (route: 'NH-29 · Dimapur', score: 78, factors: ['Rainfall', 'Basin saturation', 'Historical pattern'], window: '0-48 hrs', conf: 87),
            (route: 'NH-27 · Barpeta', score: 82, factors: ['Flood level', 'Congestion', 'Queue model'], window: '6-24 hrs', conf: 78),
            (route: 'NH-13 · Tawang', score: 74, factors: ['Seismic', 'Soil moisture', 'Rainfall'], window: '2-8 hrs', conf: 74),
          ][i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
            child: CardSurface(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(d.route, style: AppTextStyles.cardTitle)),
                      Text('${d.conf}%', style: AppTextStyles.statValue.copyWith(fontSize: 18, color: AppColors.navy900)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AccessScoreBar(score: d.score),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: d.factors.map((f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
                      child: Text(f, style: AppTextStyles.chipLabel.copyWith(fontSize: 11, color: AppColors.navy900)),
                    )).toList(),
                  ),
                  const SizedBox(height: 6),
                  Text('Window: ${d.window}', style: AppTextStyles.meta),
                ],
              ),
            ),
          );
        }),
        SectionTitle(title: 'Model performance'),
        Row(
          children: [
            Expanded(
              child: CardSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Precision', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text('89%', style: AppTextStyles.statLarge.copyWith(color: AppColors.deepGreen700)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CardSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recall', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text('82%', style: AppTextStyles.statLarge.copyWith(color: AppColors.navy900)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CardSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Latency', style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Text('1.4s', style: AppTextStyles.statLarge.copyWith(color: AppColors.saffron600)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Demo model instance. Production model runs 5-min inference cycles against NER sensor + satellite feed.', style: AppTextStyles.disclaimer),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 7. ALERTS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildAlerts() {
    final counts = {
      AlertTab.all: demoOnly(_kAlerts).length,
      AlertTab.critical: demoOnly(_kAlerts).where((e) => e.severity == AlertSeverity.critical).length,
      AlertTab.high: demoOnly(_kAlerts).where((e) => e.severity == AlertSeverity.high).length,
      AlertTab.moderate: demoOnly(_kAlerts).where((e) => e.severity == AlertSeverity.moderate).length,
      AlertTab.info: demoOnly(_kAlerts).where((e) => e.severity == AlertSeverity.info).length,
    };
    final filtered = _alertTab == AlertTab.all ? demoOnly(_kAlerts) : demoOnly(_kAlerts).where((e) {
      final m = {AlertTab.critical: AlertSeverity.critical, AlertTab.high: AlertSeverity.high, AlertTab.moderate: AlertSeverity.moderate, AlertTab.info: AlertSeverity.info};
      return e.severity == m[_alertTab];
    }).toList();

    final ico = {
      AlertSeverity.critical: Icons.warning_outlined,
      AlertSeverity.high: Icons.warning_amber_outlined,
      AlertSeverity.moderate: Icons.info_outline,
      AlertSeverity.info: Icons.notifications_outlined,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Alerts', style: AppTextStyles.pageHeading),
                  const SizedBox(height: 2),
                  Text('System, officer, and AI-generated alerts · action or dismiss.', style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: FilledButton.tonal(
                onPressed: () {},
                style: FilledButton.styleFrom(backgroundColor: AppColors.navyTint, foregroundColor: AppColors.navy900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: Text('Broadcast alert', style: AppTextStyles.buttonSmall),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip(tone: ChipTone.critical, label: 'Critical 0${counts[AlertTab.critical]}'),
            StatusChip(tone: ChipTone.saffron, label: 'High 0${counts[AlertTab.high]}'),
            StatusChip(tone: ChipTone.navy, label: 'Moderate ${counts[AlertTab.moderate]}'),
            StatusChip(tone: ChipTone.muted, label: 'Info ${counts[AlertTab.info]}'),
          ],
        ),
        const SizedBox(height: 16),
        ScrollTabs<AlertTab>(
          tabs: AlertTab.values.map((t) => ScrollTab<AlertTab>(id: t, label: t.name[0].toUpperCase() + t.name.substring(1), count: counts[t])).toList(),
          active: _alertTab,
          onChange: (v) => setState(() => _alertTab = v),
        ),
        const SizedBox(height: 16),
        ...List.generate(filtered.length, (i) {
          final a = filtered[i];
          final acked = _ackedAlerts.contains(a.id);
          return Padding(
            padding: EdgeInsets.only(bottom: i == filtered.length - 1 ? 0 : 12),
            child: CardSurface(
              leftAccentColor: a.severity == AlertSeverity.critical ? AppColors.signalRed700 : a.severity == AlertSeverity.high ? AppColors.saffron600 : Colors.transparent,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: a.severity == AlertSeverity.critical ? AppColors.criticalBg : a.severity == AlertSeverity.high ? AppColors.saffronBg : a.severity == AlertSeverity.moderate ? AppColors.navyTint : AppColors.clearBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(ico[a.severity], size: 18, color: a.severity == AlertSeverity.critical ? AppColors.signalRed700 : a.severity == AlertSeverity.high ? AppColors.saffron600 : a.severity == AlertSeverity.moderate ? AppColors.navy900 : AppColors.deepGreen700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title, style: AppTextStyles.cardTitle.copyWith(
                                color: a.severity == AlertSeverity.critical ? AppColors.signalRed700 : a.severity == AlertSeverity.high ? AppColors.saffronDark : a.severity == AlertSeverity.moderate ? AppColors.navy900 : AppColors.deepGreen700,
                              )),
                              const SizedBox(height: 3),
                              Text(a.description, style: AppTextStyles.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 12, color: AppColors.slate500),
                            const SizedBox(width: 4),
                            Expanded(child: Text(a.distance, style: AppTextStyles.caption)),
                            const SizedBox(width: 10),
                            Icon(Icons.av_timer_outlined, size: 12, color: AppColors.slate500),
                            const SizedBox(width: 4),
                            Text(a.time, style: AppTextStyles.caption),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.source_outlined, size: 12, color: AppColors.slate500),
                            const SizedBox(width: 4),
                            Expanded(child: Text('Source: ${a.source}', style: AppTextStyles.caption)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColors.navy900.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.tips_and_updates_outlined, size: 14, color: AppColors.navy900),
                              const SizedBox(width: 6),
                              Expanded(child: Text('Recommended: ${a.action}', style: AppTextStyles.bodySmall.copyWith(color: AppColors.navy900))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 34,
                                child: FilledButton.tonal(
                                  onPressed: acked ? null : () {},
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.navyTint, foregroundColor: AppColors.navy900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                  child: Text(acked ? 'Viewed' : 'View', style: AppTextStyles.buttonSmall),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 34,
                                child: OutlinedButton(
                                  onPressed: () => setState(() => _ackedAlerts.add(a.id)),
                                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.hairline), foregroundColor: AppColors.slate500, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                                  child: Text(acked ? 'Dismissed' : 'Dismiss', style: AppTextStyles.buttonSmall),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 8. ANALYTICS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildAnalytics() {
    if (!DemoMode.enabled) {
      return const DemoOffPage(
        title: 'Analytics',
        subtitle: 'Regional performance snapshot · incidents, risk, districts, logistics.',
        live: [SpatialAnalyticsPanel()],
      );
    }
    final weekBars = [
      ('Mon', [2, 1, 0], AppColors.saffron600),
      ('Tue', [3, 2, 1], AppColors.signalRed700),
      ('Wed', [4, 3, 1], AppColors.saffron600),
      ('Thu', [3, 4, 2], AppColors.saffron600),
      ('Fri', [5, 4, 3], AppColors.signalRed700),
      ('Sat', [4, 3, 2], AppColors.saffron600),
      ('Sun', [2, 1, 0], AppColors.deepGreen700),
    ];
    const riskDist = [
      (label: 'Critical', count: 6, color: AppColors.signalRed700, bg: AppColors.criticalBg, bar: 20),
      (label: 'High', count: 11, color: AppColors.saffron600, bg: AppColors.saffronBg, bar: 36),
      (label: 'Medium', count: 18, color: AppColors.navy900, bg: AppColors.navyTint, bar: 60),
      (label: 'Low', count: 24, color: AppColors.deepGreen700, bg: AppColors.clearBg, bar: 80),
    ];
    const districtPerf = [
      (name: 'Barpeta, Assam', score: 82, incidents: 5, avg: '1h 18m'),
      (name: 'Dimapur, Nagaland', score: 71, incidents: 4, avg: '52 min'),
      (name: 'Tawang, Arunachal', score: 74, incidents: 4, avg: '1h 34m'),
      (name: 'Silchar, Assam', score: 68, incidents: 3, avg: '48 min'),
      (name: 'Shillong, Meghalaya', score: 52, incidents: 3, avg: '36 min'),
      (name: 'Jorabat, Assam', score: 28, incidents: 2, avg: '22 min'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: const [DemoTag(), SizedBox(width: 8)]),
        const SizedBox(height: 6),
        Text('Analytics', style: AppTextStyles.pageHeading),
        const SizedBox(height: 2),
        Text('Regional performance snapshot · incidents, risk, districts, logistics.', style: AppTextStyles.bodySmall),
        const SpatialAnalyticsPanel(),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: const [
            KpiTile(label: 'Total incidents (7d)', value: '182', tone: KpiTone.navy, hint: 'Across 26 districts'),
            KpiTile(label: 'Avg response', value: '42m', tone: KpiTone.saffron, hint: 'Median TAT'),
            KpiTile(label: 'On-time logistics', value: '82%', tone: KpiTone.clear, hint: '54 of 66 shipments'),
            KpiTile(label: 'Accessibility score', value: '68/100', tone: KpiTone.saffron, hint: 'Regional composite'),
          ],
        ),
        SectionTitle(title: 'Incident Trends (7 day)'),
        CardSurface(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: weekBars.map((d) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ...List.generate(3, (idx) {
                              final h = d.$2[idx].toDouble() * 24;
                              final col = idx == 0 ? AppColors.deepGreen700 : idx == 1 ? AppColors.saffron600 : AppColors.signalRed700;
                              return h == 0 ? const SizedBox.shrink() : Container(
                                width: double.infinity,
                                height: h,
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2)),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: weekBars.map((d) => Expanded(child: Text(d.$1, style: AppTextStyles.caption, textAlign: TextAlign.center))).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 8, color: AppColors.deepGreen700), const SizedBox(width: 4), Text('Low', style: AppTextStyles.caption)]),
                  const SizedBox(width: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 8, color: AppColors.saffron600), const SizedBox(width: 4), Text('Medium', style: AppTextStyles.caption)]),
                  const SizedBox(width: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 8, color: AppColors.signalRed700), const SizedBox(width: 4), Text('High/Crit', style: AppTextStyles.caption)]),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(title: 'Risk Distribution'),
        Row(
          children: riskDist.map((r) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: r != riskDist.last ? 8 : 0),
                child: CardSurface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.label, style: AppTextStyles.caption.copyWith(color: r.color, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${r.count}', style: AppTextStyles.statValue.copyWith(fontSize: 22, color: r.color)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: r.bar / 100, backgroundColor: AppColors.slate500.withValues(alpha: 0.08), valueColor: AlwaysStoppedAnimation<Color>(r.color), minHeight: 5),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SectionTitle(title: 'District Performance'),
        ...List.generate(districtPerf.length, (i) {
          final d = districtPerf[i];
          return Padding(
            padding: EdgeInsets.only(bottom: i == districtPerf.length - 1 ? 0 : 8),
            child: CardSurface(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: AppTextStyles.cardTitle.copyWith(fontSize: 14)),
                        const SizedBox(height: 4),
                        AccessScoreBar(score: d.score, compact: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${d.incidents}', style: AppTextStyles.statValue.copyWith(fontSize: 18, color: AppColors.navy900)),
                        Text('incidents', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(d.avg, style: AppTextStyles.statValue.copyWith(fontSize: 18, color: AppColors.saffron600)),
                        Text('avg response', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        SectionTitle(title: 'Logistics Performance'),
        CardSurface(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  StatusChip(tone: ChipTone.clear, label: 'On-time 54'),
                  StatusChip(tone: ChipTone.saffron, label: 'Delayed 11'),
                  StatusChip(tone: ChipTone.critical, label: 'Stopped 03'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _miniBar('On-time', '82%', 82, ChipTone.clear)),
                  const SizedBox(width: 10),
                  Expanded(child: _miniBar('Delayed', '17%', 17, ChipTone.saffron)),
                  const SizedBox(width: 10),
                  Expanded(child: _miniBar('Stopped', '03%', 3, ChipTone.critical)),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(title: 'Generate Snapshot Report'),
        CardSurface(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Regional control room snapshot', style: AppTextStyles.cardTitle),
                    const SizedBox(height: 2),
                    Text('PDF · incidents + risk + logistics · as of now', style: AppTextStyles.caption),
                  ],
                ),
              ),
              SizedBox(
                height: 38,
                child: FilledButton.tonal(
                  onPressed: () {},
                  style: FilledButton.styleFrom(backgroundColor: AppColors.navyTint, foregroundColor: AppColors.navy900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text('Generate', style: AppTextStyles.buttonSmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Demo report generator — production instance integrates with NER State Control Room document pipeline.', style: AppTextStyles.disclaimer),
      ],
    );
  }

  Widget _miniBar(String label, String pct, int val, ChipTone tone) {
    final col = tone == ChipTone.clear ? AppColors.deepGreen700 : tone == ChipTone.saffron ? AppColors.saffron600 : AppColors.signalRed700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.caption),
            Text(pct, style: AppTextStyles.captionSemibold.copyWith(color: col)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: val / 100,
            backgroundColor: AppColors.slate500.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(col),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  void _openIncidentSheet(int i) {
    final inc = demoOnly(_kIncidents)[i];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.5,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.slate500.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(inc.id, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500)),
                  const Spacer(),
                  PriorityBadge(level: inc.severity),
                  const SizedBox(width: 6),
                  StatusChip(tone: inc.statusLabel == 'Resolved' ? ChipTone.clear : inc.statusLabel == 'Escalated' ? ChipTone.critical : inc.statusLabel == 'Active' ? ChipTone.saffron : ChipTone.navy, label: inc.statusLabel),
                ],
              ),
              const SizedBox(height: 6),
              Text('${inc.typeLabel} · ${inc.location}', style: AppTextStyles.pageHeading.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              Text('On ${inc.route} · reported ${inc.time} by ${inc.reporter}', style: AppTextStyles.bodySmall),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: _incidentMap(i, 160)),
              const SizedBox(height: 14),
              _detailRow('Assigned', inc.assignedOfficer == 'Unassigned' ? 'Unassigned' : inc.assignedOfficer),
              _detailRow('Severity', _pLabel(inc.severity)),
              _detailRow('Route', inc.route),
              _detailRow('District', inc.location),
              const SizedBox(height: 10),
              AiCard(
                demo: true, kind: 'Demo estimate',
                confidence: 82,
                title: 'Incident trajectory estimate',
                body: const AiCardText('Estimated 78% chance of >12 hr route impact. Recommended escalation to State Control Room and prepare 3 alternate reroute plans.'),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.4,
                children: [
                  _actBtn(Icons.verified_user_outlined, 'Verify', AppColors.navy900, AppColors.navyTint, () {}),
                  _actBtn(Icons.assignment_ind_outlined, 'Reassign', AppColors.navy900, AppColors.navyTint, () {}),
                  _actBtn(Icons.trending_up_outlined, 'Escalate', AppColors.signalRed700, AppColors.criticalBg, () {}),
                  _actBtn(Icons.check_circle_outline, 'Resolve', AppColors.deepGreen700, AppColors.clearBg, () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
