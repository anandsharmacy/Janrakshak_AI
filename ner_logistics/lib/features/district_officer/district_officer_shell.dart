import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../mock_data/mock_alerts.dart';
import '../ml/presentation/ml_widgets.dart';
import '../../mock_data/mock_districts.dart';
import '../../mock_data/mock_fleet.dart';
import '../../mock_data/mock_incidents.dart' hide mockDistricts, mockFleet;
import '../../mock_data/mock_officers.dart';
import '../../mock_data/mock_routes.dart';
import '../../mock_data/mock_tasks.dart';
import '../../mock_data/models.dart';
import '../../services/geo/geo_math.dart';
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
import 'district_drawer.dart';

enum IncTab { all, pending, active, escalated, resolved }
enum RouteTab { all, open, restricted, blocked, closed }
enum TaskTab { all, pending, inprogress, assigned, done }
enum AlertTab { all, critical, high, moderate, info }
enum LogisticsTab { all, active, delayed, atrisk, stopped }

enum ReportActions { view, download, generate }
enum ActionState { idle, loading, done }

const _kDistrictRoutes = [
  (id: 'NH-2', status: 'Blocked', tone: ChipTone.critical),
  (id: 'NH-29', status: 'Restricted', tone: ChipTone.saffron),
  (id: 'NH-27', status: 'Closed', tone: ChipTone.critical),
  (id: 'NH-39', status: 'Open', tone: ChipTone.clear),
  (id: 'NH-6', status: 'Open', tone: ChipTone.clear),
  (id: 'NH-40', status: 'Restricted', tone: ChipTone.saffron),
  (id: 'NH-37', status: 'Open', tone: ChipTone.clear),
];

class _ReportSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final ReportActions secondaryAction;
  final String secondaryLabel;
  const _ReportSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.secondaryAction,
    required this.secondaryLabel,
  });
}

class DistrictOfficerShell extends ConsumerStatefulWidget {
  final VoidCallback onSignOut;
  const DistrictOfficerShell({super.key, required this.onSignOut});

  @override
  ConsumerState<DistrictOfficerShell> createState() => _DistrictOfficerShellState();
}

class _DistrictOfficerShellState extends ConsumerState<DistrictOfficerShell> {
  DistrictNav _nav = DistrictNav.overview;
  bool _drawerOpen = false;
  bool _profileOpen = false;
  int _alertsBadge = 5;
  int _incidentsBadge = 2;

  // ── Alert ack state ──────────────────────────────────────────────
  final Map<String, bool> _acked = {};

  // ── Map state ────────────────────────────────────────────────────
  bool _mapExpanded = false;
  bool _filtersOpen = false;
  final Map<String, bool> _mapLayers = {
    'Roads': true,
    'Incidents': true,
    'Flood Risk': false,
    'Landslide Risk': false,
    'Logistics': true,
    'Infrastructure': false,
  };
  String _riskLevelFilter = 'All';
  String _timeRangeFilter = 'Last 24h';
  bool _simulationShown = false;

  // ── Incident state ───────────────────────────────────────────────
  IncTab _incTab = IncTab.all;
  Incident? _selectedIncident;
  String _severityFilter = 'All Severity';
  String _typeFilter = 'All Types';

  // ── Route state ──────────────────────────────────────────────────
  RouteTab _routeTab = RouteTab.all;

  // ── Logistics state ──────────────────────────────────────────────
  LogisticsTab _logisticsTab = LogisticsTab.all;

  // ── Task state ───────────────────────────────────────────────────
  TaskTab _taskTab = TaskTab.all;

  // ── Alert state ──────────────────────────────────────────────────
  AlertTab _alertTab = AlertTab.all;
  final Map<String, bool> _dismissedAlerts = {};

  // ── Report state ─────────────────────────────────────────────────
  late final Map<int, Map<ReportActions, ActionState>> _reportStates;
  static const List<_ReportSection> _reportSections = [
    _ReportSection(title: 'Incident Reports', subtitle: '12 total · 3 pending sync', icon: Icons.description_outlined, secondaryAction: ReportActions.download, secondaryLabel: 'Download'),
    _ReportSection(title: 'Completed Tasks', subtitle: '8 completed · 2 this week', icon: Icons.check_circle_outline, secondaryAction: ReportActions.generate, secondaryLabel: 'Generate'),
    _ReportSection(title: 'Route Inspections', subtitle: '5 inspections · last: yesterday', icon: Icons.route_outlined, secondaryAction: ReportActions.generate, secondaryLabel: 'Generate'),
    _ReportSection(title: 'Logistics Performance', subtitle: '4 reports · all synced', icon: Icons.local_shipping_outlined, secondaryAction: ReportActions.download, secondaryLabel: 'Download'),
    _ReportSection(title: 'Daily Activity Reports', subtitle: '7 days · today pending', icon: Icons.note_alt_outlined, secondaryAction: ReportActions.generate, secondaryLabel: 'Generate'),
    _ReportSection(title: 'Monthly District Report', subtitle: 'September 2026 · draft', icon: Icons.calendar_month_outlined, secondaryAction: ReportActions.generate, secondaryLabel: 'Generate'),
    _ReportSection(title: 'Quarterly Analysis', subtitle: 'Q3 2026 · archived', icon: Icons.insert_chart_outlined, secondaryAction: ReportActions.download, secondaryLabel: 'Download'),
    _ReportSection(title: 'Connectivity Summary', subtitle: '12 districts · last updated today', icon: Icons.hub_outlined, secondaryAction: ReportActions.generate, secondaryLabel: 'Generate'),
  ];

  @override
  void initState() {
    super.initState();
    _reportStates = {
      for (int i = 0; i < _reportSections.length; i++)
        i: {
          ReportActions.view: ActionState.idle,
          _reportSections[i].secondaryAction: ActionState.idle,
        },
    };
  }

  void _go(DistrictNav d) => setState(() { _nav = d; _drawerOpen = false; _selectedIncident = null; });

  /// Signed-in officer from Supabase; demo identity as fallback.
  Officer get _officer => ref.watch(currentProfileProvider)?.toOfficer() ?? districtOfficer;

  String _pageLabel() {
    switch (_nav) {
      case DistrictNav.overview:   return 'Overview';
      case DistrictNav.map:        return 'District Map';
      case DistrictNav.incidents:  return 'Incidents';
      case DistrictNav.routes:     return 'Routes';
      case DistrictNav.logistics:  return 'Logistics';
      case DistrictNav.riders:     return 'Live Riders';
      case DistrictNav.tasks:      return 'Tasks';
      case DistrictNav.ai:         return 'AI Insights';
      case DistrictNav.alerts:     return 'Alerts';
      case DistrictNav.reports:    return 'Reports';
      case DistrictNav.analytics:  return 'Analytics';
    }
  }

  Future<void> _handleReportAction(int idx, ReportActions action) async {
    setState(() => _reportStates[idx]![action] = ActionState.loading);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _reportStates[idx]![action] = ActionState.done);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _reportStates[idx]![action] = ActionState.idle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: 'District Officer · ${_pageLabel()}',
                subtitle: 'Janrakshak AI › District › ${_pageLabel()}',
                roleInitials: 'DO',
                alertCount: _alertsBadge,
                isOffline: false,
                onMenu: () => setState(() => _drawerOpen = true),
                onBell: () => _go(DistrictNav.alerts),
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
              child: DistrictDrawer(
                current: _nav,
                officer: _officer,
                incidentBadge: _incidentsBadge,
                alertBadge: _alertsBadge,
                onNavigate: _go,
                onClose: () => setState(() => _drawerOpen = false),
                onSignOut: widget.onSignOut,
              ),
            ),
          if (_profileOpen)
            Positioned.fill(
              child: ProfileSheet(
                role: AppRole.district,
                officer: _officer,
                onClose: () => setState(() => _profileOpen = false),
                onSignOut: widget.onSignOut,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_nav) {
      case DistrictNav.overview:  return _buildOverview();
      case DistrictNav.map:       return _buildMap();
      case DistrictNav.incidents: return _buildIncidents();
      case DistrictNav.routes:    return _buildRoutes();
      case DistrictNav.logistics: return _buildLogistics();
      case DistrictNav.riders:    return const LiveRidersScreen(embedded: true);
      case DistrictNav.tasks:     return _buildTasks();
      case DistrictNav.ai:        return _buildAi();
      case DistrictNav.alerts:    return _buildAlerts();
      case DistrictNav.reports:   return _buildReports();
      case DistrictNav.analytics: return _buildAnalytics();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. OVERVIEW (Dashboard)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOverview() {
    final criticalAlerts = mockAlerts.where((a) => a.severity == AlertSeverity.critical).take(3).toList();
    final queue = mockIncidents.take(5).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Page head ────────────────────────────────────────────────
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('District Operations', style: AppTextStyles.pageHeading),
            const SizedBox(height: 4),
            Text('Real-time operations overview for ${_officer.region}',
                style: AppTextStyles.bodySmall),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const DemoTag(),
          const SizedBox(height: 8),
          _TextButton(label: 'Generate Report', onTap: () => _go(DistrictNav.reports), primary: true),
        ]),
      ]),
      const SizedBox(height: 16),

      // ── KPI grid (2 cols × 3 rows) ───────────────────────────────
      _Grid(cols: 2, children: [
        KpiTile(label: 'Active Incidents', value: '24', tone: KpiTone.critical, hint: '+3 since yesterday', onTap: () => _go(DistrictNav.incidents)),
        KpiTile(label: 'Blocked Routes', value: '07', tone: KpiTone.saffron, hint: '+1 since yesterday', onTap: () => _go(DistrictNav.routes)),
        KpiTile(label: 'High-Risk Routes', value: '12', tone: KpiTone.saffron, hint: 'No change', onTap: () => _go(DistrictNav.routes)),
        KpiTile(label: 'Active Logistics', value: '86', tone: KpiTone.navy, hint: '+5 since yesterday', onTap: () => _go(DistrictNav.logistics)),
        KpiTile(label: 'Pending Reports', value: '18', tone: KpiTone.navy, hint: '3 overdue', onTap: () => _go(DistrictNav.reports)),
        KpiTile(label: 'Avg Response Time', value: '42m', tone: KpiTone.clear, hint: '-4m vs yesterday'),
      ]),

      // ── District Map section ─────────────────────────────────────
      SectionTitle(
        title: 'District Map',
        action: _TextButton(label: 'Full Map', onTap: () => _go(DistrictNav.map)),
      ),
      const SizedBox(height: 4),
      _buildMiniMap(height: 170),
      const SizedBox(height: 10),
      const MapLegend(),

      // ── Critical Alerts section ──────────────────────────────────
      SectionTitle(
        title: 'Critical Alerts',
        action: _TextButton(label: 'View All', onTap: () => _go(DistrictNav.alerts)),
      ),
      Text('3 unacknowledged', style: AppTextStyles.caption),
      const SizedBox(height: 10),
      for (int i = 0; i < criticalAlerts.length; i++) ...[
        _DashAlertCard(
          alert: criticalAlerts[i],
          acked: _acked[criticalAlerts[i].id] ?? false,
          onAck: () => setState(() => _acked[criticalAlerts[i].id] = true),
          onView: () => _go(DistrictNav.alerts),
        ),
        if (i < criticalAlerts.length - 1) const SizedBox(height: 10),
      ],

      // ── Incident Queue ───────────────────────────────────────────
      SectionTitle(title: 'Incident Queue'),
      for (int i = 0; i < queue.length; i++) ...[
        _IncidentQueueRow(incident: queue[i], onView: () {
          setState(() {
            _selectedIncident = queue[i];
            _nav = DistrictNav.incidents;
          });
        }),
        if (i < queue.length - 1) const SizedBox(height: 8),
      ],

      // ── AI Insights ──────────────────────────────────────────────
      SectionTitle(title: 'AI Insights'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _RiskPredictionRow(
            routeName: 'NH-29 · Dimapur → Kohima',
            score: 78,
            chips: const ['Topography', 'Rainfall 62%', 'Sat. 84%'],
            confidence: 87,
            timeWindow: 'Next 4–6 hours',
          ),
          const SizedBox(height: 14),
          _RiskPredictionRow(
            routeName: 'NH-27 · Barpeta',
            score: 69,
            chips: const ['River level', 'Rainfall 48%', 'Soil sat.'],
            confidence: 78,
            timeWindow: 'Next 12 hours',
          ),
          const SizedBox(height: 14),
          _RiskPredictionRow(
            routeName: 'NH-13 · Tawang sector',
            score: 54,
            chips: const ['Landslide risk', 'Incline 24°', 'Rainfall'],
            confidence: 81,
            timeWindow: 'Next 24 hours',
          ),
        ]),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. DISTRICT MAP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMap() {
    const routes = _kDistrictRoutes;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('District Map', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Situation map with risk layers, filters and simulation tools',
          style: AppTextStyles.bodySmall),
      const SizedBox(height: 16),

      // ── Filters toggle ───────────────────────────────────────────
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.tune_outlined, size: 18, color: AppColors.navy900),
            const SizedBox(width: 8),
            Expanded(child: Text('Map Filters', style: AppTextStyles.cardTitle)),
            _TextButton(
              label: _filtersOpen ? 'Hide' : 'Show',
              onTap: () => setState(() => _filtersOpen = !_filtersOpen),
            ),
            Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: AppColors.slate500),
          ]),
          if (_filtersOpen) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.hairline, height: 1),
            const SizedBox(height: 12),
            Wrap(runSpacing: 8, spacing: 8, children: [
              for (final e in _mapLayers.entries)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 32 - 16) / 2 - 4,
                  child: Row(children: [
                    NerToggle(value: e.value, onChanged: (v) => setState(() => _mapLayers[e.key] = v)),
                    const SizedBox(width: 8),
                    Text(e.key, style: AppTextStyles.bodySmall),
                  ]),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _FilterDropdown(label: 'Risk Level', value: _riskLevelFilter, items: const ['All', 'Critical', 'High', 'Medium', 'Low'], onChanged: (v) => setState(() => _riskLevelFilter = v))),
              const SizedBox(width: 10),
              Expanded(child: _FilterDropdown(label: 'Time Range', value: _timeRangeFilter, items: const ['Last 1h', 'Last 6h', 'Last 24h', 'Last 7d'], onChanged: (v) => setState(() => _timeRangeFilter = v))),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 12),

      // ── Simulate closure action ──────────────────────────────────
      Row(children: [
        Expanded(child: _ActionButton(label: 'Simulate Closure', onTap: () => setState(() => _simulationShown = !_simulationShown), saffron: true)),
      ]),
      if (_simulationShown) ...[
        const SizedBox(height: 12),
        AiCard(
          kind: 'Closure simulation · OSRM',
          title: 'NH-29 Closure at Km 44 — Impact',
          body: ClosureImpactView(query: _nh29Closure),
        ),
      ],
      const SizedBox(height: 16),

      // ── Situation map ────────────────────────────────────────────
      _buildMiniMap(height: 300, interactive: true, applyFilters: true),
      const SizedBox(height: 10),
      const DistrictMapLegend(),
      const SizedBox(height: 20),

      // ── Routes list ──────────────────────────────────────────────
      SectionTitle(title: 'Route Status'),
      for (int i = 0; i < routes.length; i++) ...[
        CardSurface(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
              child: Text(routes[i].id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('National Highway ${routes[i].id.substring(3)} corridor', style: AppTextStyles.cardTitle)),
            StatusChip(tone: routes[i].tone, label: routes[i].status),
          ]),
        ),
        if (i < routes.length - 1) const SizedBox(height: 8),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. INCIDENTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIncidents() {
    if (_selectedIncident != null) {
      return _buildIncidentDetail(_selectedIncident!);
    }

    final filtered = _filterIncidents();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Incidents', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Manage and monitor all reported incidents in the district',
          style: AppTextStyles.bodySmall),
      const SizedBox(height: 14),

      ScrollTabs<IncTab>(
        active: _incTab,
        onChange: (t) => setState(() => _incTab = t),
        tabs: const [
          ScrollTab(id: IncTab.all, label: 'All', count: 7),
          ScrollTab(id: IncTab.pending, label: 'Pending', count: 2),
          ScrollTab(id: IncTab.active, label: 'Active', count: 2),
          ScrollTab(id: IncTab.escalated, label: 'Escalated', count: 1),
          ScrollTab(id: IncTab.resolved, label: 'Resolved', count: 2),
        ],
      ),
      const SizedBox(height: 12),

      Row(children: [
        Expanded(child: _FilterDropdown(label: _severityFilter, value: _severityFilter,
          items: const ['All Severity', 'Critical', 'High', 'Medium', 'Low'],
          onChanged: (v) => setState(() => _severityFilter = v))),
        const SizedBox(width: 10),
        Expanded(child: _FilterDropdown(label: _typeFilter, value: _typeFilter,
          items: const ['All Types', 'Flood', 'Landslide', 'Road Blockage', 'Accident', 'Infra Damage'],
          onChanged: (v) => setState(() => _typeFilter = v))),
      ]),
      const SizedBox(height: 12),

      for (int i = 0; i < filtered.length; i++) ...[
        _IncidentCard(
          incident: filtered[i],
          onView: () => setState(() => _selectedIncident = filtered[i]),
          onVerify: filtered[i].verified ? null : () {},
        ),
        if (i < filtered.length - 1) const SizedBox(height: 10),
      ],
    ]);
  }

  List<Incident> _filterIncidents() {
    return mockIncidents.where((inc) {
      switch (_incTab) {
        case IncTab.all: return true;
        case IncTab.pending: return inc.statusLabel == 'Pending';
        case IncTab.active: return inc.statusLabel == 'Active';
        case IncTab.escalated: return inc.statusLabel == 'Escalated';
        case IncTab.resolved: return inc.statusLabel == 'Resolved';
      }
    }).toList();
  }

  Widget _buildIncidentDetail(Incident inc) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Back row
      InkWell(
        onTap: () => setState(() => _selectedIncident = null),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(children: [
            const Icon(Icons.arrow_back, size: 18, color: AppColors.navy900),
            const SizedBox(width: 8),
            Text('Back to Incidents', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.navy900)),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      // ID + priority row
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
          child: Text(inc.id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900))),
        const SizedBox(width: 10),
        PriorityBadge(level: inc.severity),
      ]),
      const SizedBox(height: 8),
      Text(inc.typeLabel, style: AppTextStyles.sectionHeading),
      const SizedBox(height: 4),
      Text('Reported ${inc.time} · ${inc.reporter}', style: AppTextStyles.caption),
      const SizedBox(height: 14),

      // Location map
      const _SectionLabel('Location'),
      const SizedBox(height: 6),
      _buildIncidentMap(inc),
      const SizedBox(height: 4),
      Text('${inc.location} · ${inc.route}', style: AppTextStyles.bodySmall),
      const SizedBox(height: 14),

      // Detail rows
      const _SectionLabel('Details'),
      const SizedBox(height: 6),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _DetailRow(label: 'Type', value: inc.typeLabel),
          const SizedBox(height: 8),
          _DetailRow(label: 'Severity', value: _priorityLabel(inc.severity)),
          const SizedBox(height: 8),
          _DetailRow(label: 'Location', value: inc.location),
          const SizedBox(height: 8),
          _DetailRow(label: 'Route', value: inc.route),
          const SizedBox(height: 8),
          _DetailRow(label: 'Reported by', value: inc.reporter),
          const SizedBox(height: 8),
          _DetailRow(label: 'Verified', value: inc.verified ? 'Yes' : 'No'),
          const SizedBox(height: 8),
          _DetailRow(label: 'Assigned to', value: inc.assignedOfficer),
          const SizedBox(height: 8),
          _DetailRow(label: 'Status', value: inc.statusLabel),
        ]),
      ),
      const SizedBox(height: 14),

      // AI estimate
      AiCard(
        demo: true, kind: 'Demo estimate',
        confidence: 82,
        title: 'Expected resolution window',
        body: AiCardText('Based on similar incidents, weather, and current team allocation, expect clearance within 3–5 hours. Crew ETA to site: 45 min.'),
      ),
      const SizedBox(height: 16),

      // Actions
      Row(children: [
        Expanded(child: _ActionButton(label: 'Verify', onTap: () {}, saffron: !inc.verified, primary: inc.verified)),
        const SizedBox(width: 8),
        Expanded(child: _ActionButton(label: 'Assign', onTap: () {})),
        const SizedBox(width: 8),
        Expanded(child: _ActionButton(label: 'Escalate', onTap: () {}, danger: true)),
        const SizedBox(width: 8),
        Expanded(child: _ActionButton(label: 'Resolve', onTap: () {}, success: true)),
      ]),
    ]);
  }

  String _priorityLabel(Priority p) {
    switch (p) {
      case Priority.critical: return 'Critical';
      case Priority.high: return 'High';
      case Priority.medium: return 'Medium';
      case Priority.low: return 'Low';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. ROUTES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRoutes() {
    final routes = [
      (info: RouteInfo(id: 'NH-2', name: 'NH-2 · Dimapur-Kohima', score: 82, risk: RiskLevel.caution, condition: 'Partial blockage', incidentCount: 3, weather: 'Heavy rain', updatedAt: '10 min ago',
        detail: const RouteDetail(floodRisk: 'High', landslideRisk: 'Medium', blockage: 'Km 44 · fallen debris', history: '3 blockages in last 30 days', recommendedAction: 'Divert via NH-39')), status: RouteStatus.blocked),
      (info: RouteInfo(id: 'NH-29', name: 'NH-29 · Kohima-Jessami', score: 67, risk: RiskLevel.caution, condition: 'Restricted', incidentCount: 2, weather: 'Rain', updatedAt: '22 min ago',
        detail: const RouteDetail(floodRisk: 'Medium', landslideRisk: 'High', blockage: 'None — width restricted', history: '1 restriction in last 30 days', recommendedAction: 'Single lane, light traffic only')), status: RouteStatus.restricted),
      (info: RouteInfo(id: 'NH-27', name: 'NH-27 · Guwahati-Siliguri', score: 54, risk: RiskLevel.caution, condition: 'Wet surface', incidentCount: 1, weather: 'Showers', updatedAt: '35 min ago',
        detail: const RouteDetail(floodRisk: 'Medium', landslideRisk: 'Low', blockage: 'None', history: '2 incidents in last 30 days', recommendedAction: 'Reduce speed')), status: RouteStatus.restricted),
      (info: RouteInfo(id: 'NH-39', name: 'NH-39 · Dimapur-Imphal', score: 32, risk: RiskLevel.clear, condition: 'Good', incidentCount: 0, weather: 'Cloudy', updatedAt: '1 hr ago',
        detail: const RouteDetail(floodRisk: 'Low', landslideRisk: 'Low', blockage: 'None', history: '0 incidents in last 30 days', recommendedAction: 'Normal traffic')), status: RouteStatus.open),
      (info: RouteInfo(id: 'NH-6', name: 'NH-6 · Shillong-Silchar', score: 24, risk: RiskLevel.clear, condition: 'Good', incidentCount: 0, weather: 'Clear', updatedAt: '1 hr ago',
        detail: const RouteDetail(floodRisk: 'Low', landslideRisk: 'Low', blockage: 'None', history: '1 incident in last 30 days', recommendedAction: 'Normal traffic')), status: RouteStatus.open),
      (info: RouteInfo(id: 'NH-40', name: 'NH-40 · Shillong-Guwahati', score: 48, risk: RiskLevel.caution, condition: 'Construction', incidentCount: 0, weather: 'Clear', updatedAt: '2 hr ago',
        detail: const RouteDetail(floodRisk: 'Low', landslideRisk: 'Low', blockage: 'None — construction zone', history: '0 incidents in last 30 days', recommendedAction: 'Expect delays')), status: RouteStatus.restricted),
      (info: RouteInfo(id: 'NH-13', name: 'NH-13 · Bomdila-Tawang', score: 88, risk: RiskLevel.critical, condition: 'Closed at pass', incidentCount: 1, weather: 'Heavy snow', updatedAt: '30 min ago',
        detail: const RouteDetail(floodRisk: 'Low', landslideRisk: 'High', blockage: 'Sela Pass · snow accumulation', history: '5 closures in last 30 days', recommendedAction: 'Do not attempt — hold')), status: RouteStatus.closed),
    ];

    final filtered = routes.where((r) {
      switch (_routeTab) {
        case RouteTab.all: return true;
        case RouteTab.open: return r.status == RouteStatus.open;
        case RouteTab.restricted: return r.status == RouteStatus.restricted;
        case RouteTab.blocked: return r.status == RouteStatus.blocked;
        case RouteTab.closed: return r.status == RouteStatus.closed;
      }
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Routes', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Corridor status, access scores and route-level risk details',
          style: AppTextStyles.bodySmall),
      SectionTitle(title: 'Road disruption risk (model)'),
      const MlRoutesBoard(),
      SectionTitle(title: 'Corridor status (demo data)'),

      _Grid(cols: 2, children: [
        KpiTile(label: 'Routes Monitored', value: '07', tone: KpiTone.navy),
        KpiTile(label: 'Blocked', value: '02', tone: KpiTone.critical),
        KpiTile(label: 'Restricted', value: '03', tone: KpiTone.saffron),
        KpiTile(label: 'Open', value: '02', tone: KpiTone.clear),
      ]),

      const SizedBox(height: 12),
      ScrollTabs<RouteTab>(
        active: _routeTab,
        onChange: (t) => setState(() => _routeTab = t),
        tabs: const [
          ScrollTab(id: RouteTab.all, label: 'All', count: 7),
          ScrollTab(id: RouteTab.open, label: 'Open', count: 2),
          ScrollTab(id: RouteTab.restricted, label: 'Restricted', count: 3),
          ScrollTab(id: RouteTab.blocked, label: 'Blocked', count: 1),
          ScrollTab(id: RouteTab.closed, label: 'Closed', count: 1),
        ],
      ),
      const SizedBox(height: 12),

      for (int i = 0; i < filtered.length; i++) ...[
        _RouteCard(r: filtered[i].info, status: filtered[i].status),
        if (i < filtered.length - 1) const SizedBox(height: 10),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. LOGISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLogistics() {
    final atRisk = mockFleet.where((v) => v.risk == Priority.high || v.risk == Priority.critical).toList();
    final all = mockFleet;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Logistics', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Active convoys, at-risk shipments and fleet status',
          style: AppTextStyles.bodySmall),
      const SizedBox(height: 16),

      _Grid(cols: 2, children: [
        KpiTile(label: 'Active Shipments', value: '86', tone: KpiTone.navy, hint: '+5 since 08:00'),
        KpiTile(label: 'Delayed', value: '09', tone: KpiTone.saffron, hint: '2 > 2 hours'),
        KpiTile(label: 'At Risk', value: '03', tone: KpiTone.critical, hint: 'Escalation recommended'),
        KpiTile(label: 'Stopped', value: '02', tone: KpiTone.critical, hint: 'Suspended'),
      ]),

      SectionTitle(title: 'Active Convoy Overview'),
      _buildMiniMap(height: 150, showIncidents: false),

      SectionTitle(title: 'At-Risk Convoys'),
      for (int i = 0; i < atRisk.length; i++) ...[
        CardSurface(
          leftAccentColor: atRisk[i].risk == Priority.critical ? AppColors.signalRed700 : AppColors.saffron600,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
                child: Text(atRisk[i].id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900))),
              const SizedBox(width: 10),
              Expanded(child: Text('${atRisk[i].route} → ${atRisk[i].destination}', style: AppTextStyles.cardTitle)),
              PriorityBadge(level: atRisk[i].risk),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              StatusChip(tone: atRisk[i].risk == Priority.critical ? ChipTone.critical : ChipTone.saffron, label: atRisk[i].statusLabel),
              const SizedBox(width: 10),
              Text('ETA: ${atRisk[i].eta}', style: AppTextStyles.caption),
            ]),
          ]),
        ),
        if (i < atRisk.length - 1) const SizedBox(height: 10),
      ],

      SectionTitle(title: 'All Shipments'),
      for (int i = 0; i < all.length; i++) ...[
        CardSurface(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
                child: Text(all[i].id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900))),
              const SizedBox(width: 8),
              const Text('·', style: TextStyle(color: AppColors.slate500)),
              const SizedBox(width: 8),
              Expanded(child: Text('Cargo · General supplies', style: AppTextStyles.cardTitle)),
              const SizedBox(width: 8),
              PriorityBadge(level: all[i].risk),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('Dimapur → ${all[i].destination}', style: AppTextStyles.bodySmall)),
              StatusChip(tone: _shipmentChipTone(all[i]), label: all[i].statusLabel),
            ]),
            const SizedBox(height: 4),
            Text('Route: ${all[i].route} · Location: En route', style: AppTextStyles.caption),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('ETA: ${all[i].eta}', style: AppTextStyles.bodySmallMedium)),
              if (all[i].statusLabel == 'Delayed' || all[i].statusLabel == 'At risk' || all[i].statusLabel == 'At Risk')
                Text('Delay detected', style: AppTextStyles.bodySmallMedium.copyWith(color: AppColors.saffronDark)),
              if (all[i].statusLabel == 'Stopped')
                Text('Suspended', style: AppTextStyles.bodySmallMedium.copyWith(color: AppColors.signalRed700)),
            ]),
          ]),
        ),
        if (i < all.length - 1) const SizedBox(height: 10),
      ],
    ]);
  }

  ChipTone _shipmentChipTone(FleetVehicle v) {
    switch (v.statusLabel) {
      case 'Moving': return ChipTone.clear;
      case 'On Time': return ChipTone.clear;
      case 'Delayed': return ChipTone.saffron;
      case 'At Risk': return ChipTone.saffron;
      case 'At risk': return ChipTone.saffron;
      case 'Stopped': return ChipTone.critical;
      default: return ChipTone.muted;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 6. TASKS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTasks() {
    final allTasks = buildMockTasks();
    final filtered = allTasks.where((t) {
      switch (_taskTab) {
        case TaskTab.all: return true;
        case TaskTab.pending: return t.status == TaskStatus.pending;
        case TaskTab.inprogress: return t.status == TaskStatus.inProgress;
        case TaskTab.assigned: return t.acceptedAt != null;
        case TaskTab.done: return t.status == TaskStatus.completed;
      }
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('District Tasks', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Task assignment and progress monitoring', style: AppTextStyles.bodySmall),
      const SizedBox(height: 16),

      _Grid(cols: 2, children: [
        KpiTile(label: 'Total Tasks', value: '48', tone: KpiTone.navy, hint: 'Assigned this week'),
        KpiTile(label: 'Pending', value: '14', tone: KpiTone.saffron, hint: '5 new today'),
        KpiTile(label: 'In Progress', value: '22', tone: KpiTone.navy, hint: '2 past due'),
        KpiTile(label: 'Completed', value: '12', tone: KpiTone.clear, hint: 'Today: 4'),
      ]),

      const SizedBox(height: 12),
      ScrollTabs<TaskTab>(
        active: _taskTab,
        onChange: (t) => setState(() => _taskTab = t),
        tabs: const [
          ScrollTab(id: TaskTab.all, label: 'All', count: 48),
          ScrollTab(id: TaskTab.pending, label: 'Pending', count: 14),
          ScrollTab(id: TaskTab.inprogress, label: 'In Progress', count: 22),
          ScrollTab(id: TaskTab.assigned, label: 'Assigned', count: 31),
          ScrollTab(id: TaskTab.done, label: 'Completed', count: 12),
        ],
      ),
      const SizedBox(height: 12),

      for (int i = 0; i < filtered.length; i++) ...[
        _TaskCard(task: filtered[i]),
        if (i < filtered.length - 1) const SizedBox(height: 10),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 7. AI INSIGHTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAi() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('AI Insights', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Road disruption risk from the NER model, followed by illustrative scenarios.',
          style: AppTextStyles.bodySmall),
      SectionTitle(title: 'Highest-risk segments · your district'),
      const MlTopAlertsCard(canPromote: true),
      SectionTitle(title: 'Illustrative scenarios (demo data)', action: const DemoTag()),

      AiCard(
        demo: true, kind: 'Demo scenario',
        confidence: 87,
        title: 'Flood risk — Barpeta low-lying sectors',
        body: AiCardText('Model projects 42% risk of inundation along NH-27 corridor near Barpeta within the next 6 hours. Rainfall intensity trend is accelerating. Recommended: pre-position sandbags at Km 112 underpass, alert 2 response teams, advise logistics to hold convoys at Guwahati hub.'),
      ),
      const SizedBox(height: 12),
      AiCard(
        demo: true, kind: 'Demo scenario',
        confidence: 78,
        title: 'Route closure probability — NH-29 Kohima',
        body: AiCardText('Combined topography + weather model indicates 67% chance of single-lane closure on NH-29 between Km 33 and Km 41 in the next 12 hours. Primary driver: soil saturation exceeding 81% + forecast 32 mm rainfall. Secondary factor: two active incidents within 3 km stretch.'),
      ),
      const SizedBox(height: 12),
      AiCard(
        demo: true, kind: 'Demo scenario',
        confidence: 81,
        title: 'Logistics delay anomaly — South district cluster',
        body: AiCardText('Anomaly detection flagged 7 shipments with delays exceeding 2σ (95th percentile) vs historical baseline for same day-of-week. Cluster maps to Imphal West, Churachandpur, and Bishnupur corridors. Suspicious signal: satellite shows no terrain events — potential checkpoint or administrative bottleneck. Recommend verify with on-ground FO.'),
      ),

      SectionTitle(title: 'Risk Model Details'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          _RiskPredictionRow(routeName: 'NH-29 · Dimapur → Kohima', score: 78, chips: const ['Topography', 'Rainfall 62%', 'Sat. 84%'], confidence: 87, timeWindow: 'Next 4–6 hours'),
          const SizedBox(height: 14),
          _RiskPredictionRow(routeName: 'NH-27 · Barpeta sector', score: 69, chips: const ['River level', 'Rainfall 48%', 'Soil sat.'], confidence: 78, timeWindow: 'Next 12 hours'),
          const SizedBox(height: 14),
          _RiskPredictionRow(routeName: 'NH-13 · Tawang sector', score: 54, chips: const ['Landslide risk', 'Incline 24°', 'Rainfall'], confidence: 81, timeWindow: 'Next 24 hours'),
        ]),
      ),

      SectionTitle(title: 'Model History'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Last 7-day trend', style: AppTextStyles.cardTitle),
            Text('34 predictions · 82% accuracy', style: AppTextStyles.caption),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (int d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d < 6 ? 6 : 0),
                  child: Column(children: [
                    Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][d], style: AppTextStyles.caption),
                    const SizedBox(height: 4),
                    Container(
                      height: 44,
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: [0.4, 0.6, 0.72, 0.55, 0.8, 0.9, 0.65][d],
                        widthFactor: 0.6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: [0.4, 0.6, 0.72, 0.55, 0.8, 0.9, 0.65][d] > 0.8
                                ? AppColors.signalRed700
                                : [0.4, 0.6, 0.72, 0.55, 0.8, 0.9, 0.65][d] > 0.6
                                    ? AppColors.saffron600
                                    : AppColors.deepGreen700,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 8. ALERTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAlerts() {
    final filtered = mockAlerts.where((a) {
      if (_dismissedAlerts[a.id] == true) return false;
      switch (_alertTab) {
        case AlertTab.all: return true;
        case AlertTab.critical: return a.severity == AlertSeverity.critical;
        case AlertTab.high: return a.severity == AlertSeverity.high;
        case AlertTab.moderate: return a.severity == AlertSeverity.moderate;
        case AlertTab.info: return a.severity == AlertSeverity.info;
      }
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Alerts', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('Active alerts by severity with recommended actions',
          style: AppTextStyles.bodySmall),
      const SizedBox(height: 14),

      Wrap(spacing: 8, runSpacing: 8, children: [
        StatusChip(tone: ChipTone.critical, label: 'Critical 06', icon: Icons.warning_outlined),
        StatusChip(tone: ChipTone.saffron, label: 'High 11', icon: Icons.warning_amber_outlined),
        StatusChip(tone: ChipTone.navy, label: 'Moderate 18'),
        StatusChip(tone: ChipTone.muted, label: 'Info 24', icon: Icons.info_outline),
      ]),

      const SizedBox(height: 14),
      ScrollTabs<AlertTab>(
        active: _alertTab,
        onChange: (t) => setState(() => _alertTab = t),
        tabs: const [
          ScrollTab(id: AlertTab.all, label: 'All', count: 59),
          ScrollTab(id: AlertTab.critical, label: 'Critical', count: 6),
          ScrollTab(id: AlertTab.high, label: 'High', count: 11),
          ScrollTab(id: AlertTab.moderate, label: 'Moderate', count: 18),
          ScrollTab(id: AlertTab.info, label: 'Info', count: 24),
        ],
      ),
      const SizedBox(height: 12),

      for (int i = 0; i < filtered.length; i++) ...[
        _AlertFullCard(
          alert: filtered[i],
          onDismiss: () => setState(() => _dismissedAlerts[filtered[i].id] = true),
          onView: () {},
        ),
        if (i < filtered.length - 1) const SizedBox(height: 10),
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 9. REPORTS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReports() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Reports', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('District reports · ${_officer.region}', style: AppTextStyles.bodySmall),
      const SizedBox(height: 6),
      const DemoTag(),
      const SizedBox(height: 16),

      for (int i = 0; i < _reportSections.length; i++) ...[
        _ReportSectionCard(
          data: _reportSections[i],
          viewState: _reportStates[i]![ReportActions.view]!,
          secondaryState: _reportStates[i]![_reportSections[i].secondaryAction]!,
          onView: () => _handleReportAction(i, ReportActions.view),
          onSecondary: () => _handleReportAction(i, _reportSections[i].secondaryAction),
        ),
        if (i < _reportSections.length - 1) const SizedBox(height: 12),
      ],

      const SizedBox(height: 16),
      Text(
        'Reports auto-generate daily at 23:59. District-level reports require DO sign-off before submission to Control Room.',
        style: AppTextStyles.disclaimer,
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 10. ANALYTICS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAnalytics() {
    final topDistricts = mockDistricts.sublist(0, 6);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Analytics', style: AppTextStyles.pageHeading),
      const SizedBox(height: 4),
      Text('District-level performance, trends and distribution',
          style: AppTextStyles.bodySmall),
      const SpatialAnalyticsPanel(),
      const SizedBox(height: 16),

      _Grid(cols: 2, children: [
        KpiTile(label: 'Total Incidents (MTD)', value: '184', tone: KpiTone.navy, hint: '+21 vs last month'),
        KpiTile(label: 'Critical Incidents', value: '22', tone: KpiTone.critical, hint: '3 unresolved'),
        KpiTile(label: 'Avg Resolution Time', value: '3h 42m', tone: KpiTone.saffron, hint: '+18m vs target'),
        KpiTile(label: 'On-time Logistics %', value: '89%', tone: KpiTone.clear, hint: '-2% vs last week'),
      ]),

      SectionTitle(title: 'Incident Trends (7-day)'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          const SizedBox(height: 6),
          Row(children: [
            for (int d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d < 6 ? 6 : 0),
                  child: Column(children: [
                    SizedBox(
                      height: 90,
                      child: Stack(children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.slate500.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0, right: 0, bottom: 0,
                          child: FractionallySizedBox(
                            heightFactor: [0.35, 0.55, 0.8, 0.45, 0.7, 0.92, 0.5][d],
                            widthFactor: 0.75,
                            alignment: Alignment.bottomCenter,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: [0.35, 0.55, 0.8, 0.45, 0.7, 0.92, 0.5][d] > 0.8
                                      ? AppColors.signalRed700
                                      : [0.35, 0.55, 0.8, 0.45, 0.7, 0.92, 0.5][d] > 0.6
                                          ? AppColors.saffron600
                                          : AppColors.deepGreen700,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d], style: AppTextStyles.caption),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.deepGreen700, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('Low', style: AppTextStyles.caption),
            ]),
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.saffron600, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('Medium', style: AppTextStyles.caption),
            ]),
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.signalRed700, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('High', style: AppTextStyles.caption),
            ]),
          ]),
        ]),
      ),

      SectionTitle(title: 'Risk Distribution'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          SizedBox(
            height: 140,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 180, height: 180,
                child: CustomPaint(painter: _PiePainter(segments: const [
                  (0.42, AppColors.signalRed700),
                  (0.31, AppColors.saffron600),
                  (0.18, AppColors.navy900),
                  (0.09, AppColors.deepGreen700),
                ])),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('184', style: AppTextStyles.statValue),
                  Text('Total', style: AppTextStyles.caption),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 6, alignment: WrapAlignment.center, children: const [
            _LegendDot(color: AppColors.signalRed700, label: 'Critical · 42%'),
            _LegendDot(color: AppColors.saffron600, label: 'High · 31%'),
            _LegendDot(color: AppColors.navy900, label: 'Medium · 18%'),
            _LegendDot(color: AppColors.deepGreen700, label: 'Low · 9%'),
          ]),
        ]),
      ),

      SectionTitle(title: 'Response Time by District (Top 6)'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          for (int i = 0; i < topDistricts.length; i++) ...[
            Row(children: [
              SizedBox(width: 110, child: Text('${topDistricts[i].name}, ${topDistricts[i].state}', style: AppTextStyles.cardTitle, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 10),
              Expanded(child: AccessScoreBar(score: topDistricts[i].accessScore, compact: true)),
              const SizedBox(width: 10),
              SizedBox(width: 54, child: Text('${(topDistricts[i].accessScore * 0.5).round()}m avg', style: AppTextStyles.caption, textAlign: TextAlign.right)),
            ]),
            if (i < topDistricts.length - 1) const SizedBox(height: 12),
          ],
        ]),
      ),

      SectionTitle(title: 'Logistics Performance'),
      CardSurface(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            StatusChip(tone: ChipTone.clear, label: 'On Time · 77'),
            StatusChip(tone: ChipTone.saffron, label: 'Delayed · 09'),
            StatusChip(tone: ChipTone.critical, label: 'Stopped · 02'),
            StatusChip(tone: ChipTone.muted, label: 'Awaiting dispatch · 04'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _PerfTile(label: 'On-time rate', value: '89%', tone: KpiTone.clear)),
            const SizedBox(width: 10),
            Expanded(child: _PerfTile(label: 'Avg delay', value: '+36m', tone: KpiTone.saffron)),
            const SizedBox(width: 10),
            Expanded(child: _PerfTile(label: 'At risk', value: '03', tone: KpiTone.critical)),
          ]),
        ]),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Shared subwidgets
  // ═══════════════════════════════════════════════════════════════════════════

  MapLineTone _mapTone(String route) {
    final id = NerGeo.routeIdOf(route);
    if (_simulationShown && id == 'NH-29') return MapLineTone.critical;
    for (final r in _kDistrictRoutes) {
      if (r.id != id) continue;
      return switch (r.tone) {
        ChipTone.critical => MapLineTone.critical,
        ChipTone.saffron => MapLineTone.caution,
        _ => MapLineTone.clear,
      };
    }
    return MapLineTone.clear;
  }

  /// Lowest incident severity shown for the Map tab's risk-level filter.
  Priority get _riskFloor => switch (_riskLevelFilter) {
        'Critical' => Priority.critical,
        'High' => Priority.high,
        'Medium' => Priority.medium,
        _ => Priority.low,
      };

  MapIncident _mapIncident(Incident inc) => MapIncident(
        id: inc.id,
        point: NerGeo.locate(inc.location, inc.route),
        severity: inc.severity,
        type: inc.type,
        label: '${inc.id} · ${inc.typeLabel} · ${inc.location}',
        resolved: inc.statusLabel == 'Resolved',
      );

  void _openIncidentById(String id) {
    for (final inc in mockIncidents) {
      if (inc.id != id) continue;
      setState(() {
        _selectedIncident = inc;
        _nav = DistrictNav.incidents;
      });
      return;
    }
  }

  /// District situation map. Previews are static; [applyFilters] honours the
  /// Map tab's layer toggles and risk-level filter.
  /// The simulated NH-29 closure (Km 44), routed through OSRM per convoy.
  static final _nh29Closure = ClosureQuery(
    routeId: 'NH-29',
    closurePoint: GeoMath.pointAtM(NerGeo.highways['NH-29']!, 44000),
    convoys: ConvoyTrip.fromFleet(mockFleet),
  );

  /// District situation map. Previews are static; [applyFilters] honours the
  /// Map tab's layer toggles and risk-level filter. Risk zones come from
  /// GeoServer WMS when configured, else local circles.
  Widget _buildMiniMap({
    double height = 170,
    bool interactive = false,
    bool applyFilters = false,
    bool showIncidents = true,
  }) {
    bool on(String layer) => !applyFilters || (_mapLayers[layer] ?? false);
    final routes = NerGeo.routes({for (final r in _kDistrictRoutes) r.id: _mapTone(r.id)});
    final gs = ref.watch(geoServerClientProvider);
    return CardSurface(
      child: SizedBox(
        height: height,
        child: NerMap(
          interactive: interactive,
          showControls: interactive,
          showRouteLabels: interactive,
          onIncidentTap: interactive ? _openIncidentById : null,
          onLongPress: interactive ? (p) => showLocationInsight(context, p) : null,
          fitPoints: [for (final r in routes) ...r.points],
          fitPadding: EdgeInsets.all(interactive ? 28 : 10),
          routes: [
            if (on('Roads')) ...routes,
            if (interactive && _simulationShown) ...closureRoutes(ref, _nh29Closure),
          ],
          wmsOverlays: applyFilters
              ? nerWmsOverlays(gs,
                  flood: on('Flood Risk'), landslide: on('Landslide Risk'))
              : const [],
          zones: [
            if (applyFilters) ...NerGeo.safeZones,
            if (gs == null && applyFilters && on('Flood Risk')) ...NerGeo.floodZones,
            if (gs == null && applyFilters && on('Landslide Risk')) ...NerGeo.landslideZones,
          ],
          pois: applyFilters && on('Infrastructure') ? NerGeo.infrastructure : const [],
          // Demo fleet + every live rider from the mobile app (Supabase Realtime).
          vehicles: on('Logistics')
              ? [
                  ...NerGeo.vehicles(mockFleet),
                  ...liveRiderVehicles(ref.watch(liveRidersProvider).valueOrNull),
                ]
              : const [],
          incidents: [
            if (showIncidents && on('Incidents'))
              for (final inc in mockIncidents)
                if (!applyFilters || inc.severity.index <= _riskFloor.index) _mapIncident(inc),
          ],
        ),
      ),
    );
  }

  /// Static location preview centred on one incident.
  Widget _buildIncidentMap(Incident inc, {double height = 140}) {
    final point = NerGeo.locate(inc.location, inc.route);
    final line = NerGeo.highway(inc.route);
    return CardSurface(
      child: SizedBox(
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
          incidents: [_mapIncident(inc)],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Outside-class shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _Grid extends StatelessWidget {
  final int cols;
  final List<Widget> children;
  const _Grid({required this.cols, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += cols) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < cols; j++) {
        final idx = i + j;
        if (idx < children.length) {
          if (j > 0) rowChildren.add(const SizedBox(width: 10));
          rowChildren.add(Expanded(child: children[idx]));
        } else {
          if (j > 0) rowChildren.add(const SizedBox(width: 10));
          rowChildren.add(const Expanded(child: SizedBox.shrink()));
        }
      }
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren));
      if (i + cols < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _TextButton({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          style: AppTextStyles.buttonSmall.copyWith(
            color: primary ? AppColors.navy900 : AppColors.slate500,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool saffron;
  final bool danger;
  final bool success;
  const _ActionButton({required this.label, this.onTap, this.primary = false, this.saffron = false, this.danger = false, this.success = false});

  Color get _fg {
    if (danger) return AppColors.signalRed700;
    if (success) return AppColors.deepGreen700;
    if (saffron) return AppColors.saffronDark;
    if (primary) return Colors.white;
    return AppColors.navy900;
  }
  Color get _bg {
    if (danger) return AppColors.criticalBg;
    if (success) return AppColors.clearBg;
    if (saffron) return AppColors.saffronBg;
    if (primary) return AppColors.navy900;
    return Colors.transparent;
  }
  Color get _border {
    if (danger) return AppColors.signalRed700.withValues(alpha: 0.4);
    if (success) return AppColors.deepGreen700.withValues(alpha: 0.4);
    if (saffron) return AppColors.saffron600.withValues(alpha: 0.4);
    if (primary) return AppColors.navy900;
    return AppColors.navy900.withValues(alpha: 0.25);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: disabled ? _bg.withValues(alpha: 0.5) : _bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: disabled ? _border.withValues(alpha: 0.5) : _border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTextStyles.buttonSmall.copyWith(
            color: disabled ? _fg.withValues(alpha: 0.5) : _fg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DashAlertCard extends StatelessWidget {
  final AppAlert alert;
  final bool acked;
  final VoidCallback onAck;
  final VoidCallback onView;

  const _DashAlertCard({required this.alert, required this.acked, required this.onAck, required this.onView});

  @override
  Widget build(BuildContext context) {
    final isCritical = alert.severity == AlertSeverity.critical;
    return CardSurface(
      leftAccentColor: isCritical ? AppColors.signalRed700 : AppColors.saffron600,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(alert.title, style: AppTextStyles.cardTitle)),
          PriorityBadge(level: _toPriority(alert.severity)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.location_on_outlined, size: 14, color: AppColors.slate500),
          const SizedBox(width: 4),
          Text('${alert.distance} · ${alert.time}', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: 2),
        Text('Source: ${alert.recommendedAction.split(' ').first}', style: AppTextStyles.caption),
        const SizedBox(height: 10),
        Row(children: [
          _TextButton(label: 'View', onTap: onView, primary: true),
          const SizedBox(width: 12),
          acked
              ? Row(children: [
                  const Icon(Icons.check_circle, size: 14, color: AppColors.deepGreen700),
                  const SizedBox(width: 4),
                  Text('Acknowledged', style: AppTextStyles.buttonSmall.copyWith(color: AppColors.deepGreen700)),
                ])
              : _TextButton(label: 'Acknowledge', onTap: onAck),
        ]),
      ]),
    );
  }

  static Priority _toPriority(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.critical: return Priority.critical;
      case AlertSeverity.high: return Priority.high;
      case AlertSeverity.moderate: return Priority.medium;
      case AlertSeverity.info: return Priority.low;
    }
  }
}

class _IncidentQueueRow extends StatelessWidget {
  final Incident incident;
  final VoidCallback onView;

  const _IncidentQueueRow({required this.incident, required this.onView});

  ChipTone get _statusChip {
    switch (incident.statusLabel) {
      case 'Pending': return ChipTone.saffron;
      case 'Active': return ChipTone.navy;
      case 'Escalated': return ChipTone.critical;
      case 'Resolved': return ChipTone.clear;
      default: return ChipTone.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
          child: Text(incident.id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(incident.typeLabel, style: AppTextStyles.cardTitle)),
              const SizedBox(width: 8),
              PriorityBadge(level: incident.severity),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.location_on_outlined, size: 12, color: AppColors.slate500),
              const SizedBox(width: 3),
              Expanded(child: Text('${incident.location} · ${incident.route}', style: AppTextStyles.caption)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          StatusChip(tone: _statusChip, label: incident.statusLabel),
          const SizedBox(height: 6),
          _TextButton(label: 'View', onTap: onView, primary: true),
        ]),
      ]),
    );
  }
}

class _RiskPredictionRow extends StatelessWidget {
  final String routeName;
  final int score;
  final List<String> chips;
  final int confidence;
  final String timeWindow;

  const _RiskPredictionRow({required this.routeName, required this.score, required this.chips, required this.confidence, required this.timeWindow});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(routeName, style: AppTextStyles.cardTitle),
      const SizedBox(height: 6),
      AccessScoreBar(score: score),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.slate500.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(c, style: AppTextStyles.chipLabel.copyWith(color: AppColors.slate500)),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Text('$confidence% confidence', style: AppTextStyles.captionSemibold),
        const Spacer(),
        Text(timeWindow, style: AppTextStyles.caption),
      ]),
    ]);
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          value: value,
          style: AppTextStyles.bodySmallMedium,
          onChanged: (v) => onChanged(v ?? value),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final Incident incident;
  final VoidCallback onView;
  final VoidCallback? onVerify;

  const _IncidentCard({required this.incident, required this.onView, this.onVerify});

  ChipTone get _statusChip {
    switch (incident.statusLabel) {
      case 'Pending': return ChipTone.saffron;
      case 'Active': return ChipTone.navy;
      case 'Escalated': return ChipTone.critical;
      case 'Resolved': return ChipTone.clear;
      default: return ChipTone.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      leftAccentColor: incident.statusLabel == 'Escalated' ? AppColors.signalRed700 : null,
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
            child: Text(incident.id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(incident.typeLabel, style: AppTextStyles.cardTitle)),
          const SizedBox(width: 8),
          PriorityBadge(level: incident.severity),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.location_on_outlined, size: 13, color: AppColors.slate500),
          const SizedBox(width: 3),
          Expanded(child: Text('${incident.location} · ${incident.route}', style: AppTextStyles.caption)),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          Icon(Icons.person_outline, size: 13, color: AppColors.slate500),
          const SizedBox(width: 3),
          Text(incident.reporter, style: AppTextStyles.caption),
          const SizedBox(width: 10),
          Icon(Icons.schedule_outlined, size: 13, color: AppColors.slate500),
          const SizedBox(width: 3),
          Text(incident.time, style: AppTextStyles.caption),
          const Spacer(),
          if (incident.verified)
            Row(children: [
              const Icon(Icons.verified_outlined, size: 13, color: AppColors.deepGreen700),
              const SizedBox(width: 3),
              Text('Verified', style: AppTextStyles.caption.copyWith(color: AppColors.deepGreen700)),
            ])
          else
            Text('Unverified', style: AppTextStyles.caption.copyWith(color: AppColors.saffronDark)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('Assigned: ${incident.assignedOfficer}', style: AppTextStyles.bodySmall)),
          StatusChip(tone: _statusChip, label: incident.statusLabel),
          const SizedBox(width: 8),
          _ActionButton(label: 'View', onTap: onView, primary: true),
        ]),
        if (onVerify != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _ActionButton(label: 'Verify Incident', onTap: onVerify, success: true)),
          ]),
        ],
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTextStyles.eyebrowMd.copyWith(color: AppColors.slate500));
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 100, child: Text(label, style: AppTextStyles.caption)),
      Expanded(child: Text(value, style: AppTextStyles.bodySmallMedium)),
    ]);
  }
}

class _RouteCard extends StatelessWidget {
  final RouteInfo r;
  final RouteStatus status;

  const _RouteCard({required this.r, required this.status});

  ChipTone get _tone {
    switch (status) {
      case RouteStatus.open: return ChipTone.clear;
      case RouteStatus.restricted: return ChipTone.saffron;
      case RouteStatus.blocked: return ChipTone.critical;
      case RouteStatus.closed: return ChipTone.critical;
    }
  }
  String get _statusLabel {
    switch (status) {
      case RouteStatus.open: return 'Open';
      case RouteStatus.restricted: return 'Restricted';
      case RouteStatus.blocked: return 'Blocked';
      case RouteStatus.closed: return 'Closed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
            child: Text(r.id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(r.name, style: AppTextStyles.cardTitle)),
          const SizedBox(width: 8),
          StatusChip(tone: _tone, label: _statusLabel),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('${r.detail.blockage.isEmpty ? r.condition : r.detail.blockage}', style: AppTextStyles.bodySmall)),
          Text('Updated ${r.updatedAt}', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Access Score', style: AppTextStyles.eyebrow.copyWith(color: AppColors.slate500)),
              const SizedBox(height: 3),
              AccessScoreBar(score: r.score, compact: true),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          Text('Weather: ${r.weather}', style: AppTextStyles.caption),
          Text('Incidents: ${r.incidentCount}', style: AppTextStyles.caption),
          Text('Rec: ${r.detail.recommendedAction}', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: _TextButton(label: 'View details', onTap: () {}, primary: true)),
      ]),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final FieldTask task;

  const _TaskCard({required this.task});

  ChipTone get _tone {
    switch (task.status) {
      case TaskStatus.pending: return ChipTone.saffron;
      case TaskStatus.inProgress: return ChipTone.navy;
      case TaskStatus.awaitingVerification: return ChipTone.saffron;
      case TaskStatus.completed: return ChipTone.clear;
      case TaskStatus.overdue: return ChipTone.critical;
    }
  }
  String get _label {
    switch (task.status) {
      case TaskStatus.pending: return 'Pending';
      case TaskStatus.inProgress: return 'In Progress';
      case TaskStatus.awaitingVerification: return 'Awaiting Verification';
      case TaskStatus.completed: return 'Completed';
      case TaskStatus.overdue: return 'Overdue';
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(4)),
            child: Text(task.id, style: AppTextStyles.chipLabel.copyWith(color: AppColors.navy900)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(task.title, style: AppTextStyles.cardTitle)),
          const SizedBox(width: 8),
          PriorityBadge(level: task.priority),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.location_on_outlined, size: 13, color: AppColors.slate500),
          const SizedBox(width: 3),
          Expanded(child: Text(task.location, style: AppTextStyles.caption)),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          Icon(Icons.event_outlined, size: 13, color: AppColors.slate500),
          const SizedBox(width: 3),
          Text('Due ${task.dueTime}', style: AppTextStyles.caption),
          const SizedBox(width: 12),
          Icon(Icons.person_outline, size: 13, color: AppColors.slate500),
          const SizedBox(width: 3),
          Text('FO — Unassigned', style: AppTextStyles.caption),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          StatusChip(tone: _tone, label: _label),
          const Spacer(),
          _TextButton(label: 'Assign', onTap: () {}),
          const SizedBox(width: 6),
          _ActionButton(label: 'View', onTap: () {}, primary: true),
        ]),
      ]),
    );
  }
}

class _AlertFullCard extends StatelessWidget {
  final AppAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onView;

  const _AlertFullCard({required this.alert, required this.onDismiss, required this.onView});

  BannerTone get _tone {
    switch (alert.severity) {
      case AlertSeverity.critical: return BannerTone.critical;
      case AlertSeverity.high: return BannerTone.caution;
      case AlertSeverity.moderate: return BannerTone.caution;
      case AlertSeverity.info: return BannerTone.clear;
    }
  }
  IconData get _icon {
    switch (alert.severity) {
      case AlertSeverity.critical: return Icons.warning_outlined;
      case AlertSeverity.high: return Icons.warning_amber_outlined;
      case AlertSeverity.moderate: return Icons.info_outline;
      case AlertSeverity.info: return Icons.info_outline;
    }
  }
  Color get _iconColor {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.signalRed700;
      case AlertSeverity.high: return AppColors.saffron600;
      case AlertSeverity.moderate: return AppColors.saffron600;
      case AlertSeverity.info: return AppColors.deepGreen700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      leftAccentColor: alert.severity == AlertSeverity.critical ? AppColors.signalRed700 : null,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _toneBg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: _toneBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon, size: 20, color: _iconColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                alert.title,
                                style: AppTextStyles.cardTitle.copyWith(
                                  color: alert.severity == AlertSeverity.critical
                                      ? AppColors.signalRed700
                                      : alert.severity == AlertSeverity.info
                                          ? AppColors.deepGreen700
                                          : AppColors.saffronDark,
                                ),
                              ),
                            ),
                            StatusChip(
                              tone: alert.severity == AlertSeverity.critical
                                  ? ChipTone.critical
                                  : alert.severity == AlertSeverity.high
                                      ? ChipTone.saffron
                                      : alert.severity == AlertSeverity.moderate
                                          ? ChipTone.navy
                                          : ChipTone.clear,
                              label: alert.severity.name.toUpperCase(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          alert.description,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.navy900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: AppColors.slate500),
                            const SizedBox(width: 3),
                            Text(alert.distance, style: AppTextStyles.caption),
                            const SizedBox(width: 10),
                            Icon(Icons.schedule_outlined,
                                size: 13, color: AppColors.slate500),
                            const SizedBox(width: 3),
                            Text(alert.time, style: AppTextStyles.caption),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Recommended: ${alert.recommendedAction}',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w500,
                            color: AppColors.navy900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _ActionButton(
                                label: 'View', onTap: onView, primary: true),
                            const SizedBox(width: 8),
                            _ActionButton(label: 'Dismiss', onTap: onDismiss),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _toneBg {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.criticalBg;
      case AlertSeverity.high: return AppColors.saffronBg;
      case AlertSeverity.moderate: return AppColors.saffronBg;
      case AlertSeverity.info: return AppColors.clearBg;
    }
  }
  Color get _toneBorder {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.signalRed700.withValues(alpha: 0.3);
      case AlertSeverity.high: return AppColors.saffron600.withValues(alpha: 0.3);
      case AlertSeverity.moderate: return AppColors.saffron600.withValues(alpha: 0.3);
      case AlertSeverity.info: return AppColors.deepGreen700.withValues(alpha: 0.3);
    }
  }
}

class _ReportSectionCard extends StatelessWidget {
  final _ReportSection data;
  final ActionState viewState;
  final ActionState secondaryState;
  final VoidCallback onView;
  final VoidCallback onSecondary;

  const _ReportSectionCard({required this.data, required this.viewState, required this.secondaryState, required this.onView, required this.onSecondary});

  String _viewL(ActionState s) => s == ActionState.idle ? 'View' : s == ActionState.loading ? 'Loading…' : 'Done';
  String _secL(ReportActions a, ActionState s) {
    if (s == ActionState.loading) return a == ReportActions.download ? 'Downloading…' : 'Generating…';
    if (s == ActionState.done) return 'Done';
    return a == ReportActions.download ? 'Download' : 'Generate';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.hairline, width: 1)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.navy900.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(data.icon, color: AppColors.navy900, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data.title, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 2),
                  Text(data.subtitle, style: AppTextStyles.bodySmall),
                ]),
              ),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _ReportActionButton(label: _viewL(viewState), isPrimary: true, state: viewState, onTap: onView),
                const SizedBox(width: 8),
                _ReportActionButton(label: _secL(data.secondaryAction, secondaryState), isPrimary: false, state: secondaryState, onTap: onSecondary),
              ]),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _ReportActionButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final ActionState state;
  final VoidCallback onTap;

  const _ReportActionButton({required this.label, required this.isPrimary, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = state == ActionState.loading || state == ActionState.done;
    final bc = isPrimary ? AppColors.navy900 : AppColors.ink.withValues(alpha: 0.30);
    final tc = isPrimary ? AppColors.navy900 : AppColors.ink;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: bc, width: 1),
          color: state == ActionState.done ? (isPrimary ? AppColors.navy900.withValues(alpha: 0.08) : AppColors.ink.withValues(alpha: 0.08)) : Colors.transparent,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (state == ActionState.loading) ...[
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(tc))),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(fontFamily: 'PublicSans', fontSize: 13, fontWeight: FontWeight.w600, color: state == ActionState.done ? (isPrimary ? AppColors.navy900 : AppColors.ink) : tc, height: 1.0)),
        ]),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: AppTextStyles.caption),
    ]);
  }
}

class _PerfTile extends StatelessWidget {
  final String label;
  final String value;
  final KpiTone tone;
  const _PerfTile({required this.label, required this.value, required this.tone});

  Color get _c {
    switch (tone) {
      case KpiTone.navy: return AppColors.navy900;
      case KpiTone.critical: return AppColors.signalRed700;
      case KpiTone.saffron: return AppColors.saffron600;
      case KpiTone.clear: return AppColors.deepGreen700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.navyTint, borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.slate500)),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.statLarge.copyWith(color: _c)),
      ]),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<(double, Color)> segments;
  const _PiePainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    double start = -1.5708;
    for (final (frac, color) in segments) {
      final sweep = frac * 2 * 3.14159;
      final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 34;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - 12), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.segments != segments;
}
