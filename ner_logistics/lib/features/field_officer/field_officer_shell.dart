import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../mock_data/mock_officers.dart';
import '../auth/application/auth_controller.dart';
import '../tracking/presentation/live_riders_screen.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../features/profile/profile_sheet.dart';
import '../../mock_data/models.dart';
import 'field_drawer.dart';
import 'dashboard/field_dashboard.dart';
import 'trip/route_screen.dart';
import 'tasks/my_tasks_screen.dart';
import 'report/report_screen.dart';
import 'alerts/alerts_screen.dart';
import 'route_status/route_status_screen.dart';
import 'logistics/logistics_screen.dart';
import 'reports/reports_screen.dart';

/// FieldOfficerShell — top-level widget for the Field Officer track.
/// Owns nav state, drawer, header, offline toggle, and profile sheet.
/// All sub-screens are rendered as children — no Navigator push.
class FieldOfficerShell extends ConsumerStatefulWidget {
  final VoidCallback onSignOut;

  const FieldOfficerShell({super.key, required this.onSignOut});

  @override
  ConsumerState<FieldOfficerShell> createState() => _FieldOfficerShellState();
}

class _FieldOfficerShellState extends ConsumerState<FieldOfficerShell> {
  /// Signed-in officer from Supabase; demo identity as fallback.
  Officer get _officer => ref.watch(currentProfileProvider)?.toOfficer() ?? fieldOfficer;

  FieldNav _nav = FieldNav.dashboard;
  bool _drawerOpen = false;
  bool _profileOpen = false;
  bool _isOffline = false;
  int _alertsBadge = 0;

  // Trip state — lifted here so the header subtitle can reflect it
  TripPhase _tripPhase = TripPhase.active;
  bool _postReroute = false;
  bool _riskUpgraded = false;

  void _go(FieldNav dest) {
    setState(() {
      _nav = dest;
      _drawerOpen = false;
    });
  }

  void _triggerRisk() {
    setState(() {
      _nav = FieldNav.trip;
      if (_tripPhase == TripPhase.active && !_postReroute) {
        _tripPhase = TripPhase.interrupt;
        _alertsBadge = 1;
      }
    });
  }

  void _setTripPhase(TripPhase phase) {
    setState(() {
      _tripPhase = phase;
      if (phase == TripPhase.interrupt && !_postReroute) {
        _alertsBadge = 1;
      }
    });
  }

  String get _headerTitle {
    switch (_nav) {
      case FieldNav.dashboard:  return 'Field Officer Dashboard';
      case FieldNav.trip:
        if (_tripPhase == TripPhase.rerouted || _postReroute) {
          return 'Active trip · rerouted';
        }
        return 'Active trip';
      case FieldNav.tasks:      return 'My Tasks';
      case FieldNav.report:     return 'Report Incident';
      case FieldNav.route:      return 'Route Status';
      case FieldNav.logistics:  return 'Logistics';
      case FieldNav.riders:     return 'Live Riders';
      case FieldNav.alerts:     return 'Alerts';
      case FieldNav.reports:    return 'My Reports';
    }
  }

  String get _headerSubtitle {
    switch (_nav) {
      case FieldNav.dashboard:
        return '${_officer.name} · ${_officer.region}';
      case FieldNav.trip:
        if (_tripPhase == TripPhase.interrupt ||
            _tripPhase == TripPhase.calculating) {
          return 'TRP-2291 · risk update received';
        }
        if (_tripPhase == TripPhase.rerouted || _postReroute) {
          return 'TRP-2291 · control room notified';
        }
        return 'TRP-2291 · Consignment P1 medical';
      case FieldNav.tasks:      return 'Assigned to you · ${_officer.region}';
      case FieldNav.report:     return 'GPS-tagged · saves offline first';
      case FieldNav.route:      return 'Routes · ${_officer.region}';
      case FieldNav.logistics:  return 'Active shipments · ${_officer.region}';
      case FieldNav.riders:     return 'All riders on duty · live positions';
      case FieldNav.alerts:     return 'Active today · ${_officer.region}';
      case FieldNav.reports:    return '${_officer.region} · all reports';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F1),
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                title: _headerTitle,
                subtitle: _headerSubtitle,
                roleInitials: 'FO',
                alertCount: _alertsBadge,
                isOffline: _isOffline,
                onMenu: () => setState(() => _drawerOpen = true),
                onBell: () => _go(FieldNav.alerts),
                onAvatar: () => setState(() => _profileOpen = true),
                onSubtitleDoubleTap: _nav == FieldNav.trip
                    ? _triggerRisk
                    : null,
              ),
              OfflineBanner(isOffline: _isOffline),
              Expanded(child: _buildBody()),
            ],
          ),

          // Drawer overlay
          if (_drawerOpen)
            Positioned.fill(
              child: FieldDrawer(
                current: _nav,
                officer: _officer,
                alertCount: _alertsBadge,
                onNavigate: _go,
                onClose: () => setState(() => _drawerOpen = false),
                onSignOut: widget.onSignOut,
              ),
            ),

          // Profile sheet overlay
          if (_profileOpen)
            Positioned.fill(
              child: ProfileSheet(
                role: AppRole.field,
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
      case FieldNav.dashboard:
        return FieldDashboard(
          isOffline: _isOffline,
          officer: _officer,
          onToggleOffline: () =>
              setState(() => _isOffline = !_isOffline),
          onStartTask: () => _go(FieldNav.trip),
          onOpenTasks: () => _go(FieldNav.tasks),
          onViewIncidents: () => _go(FieldNav.alerts),
          onReportType: (type) {
            setState(() => _nav = FieldNav.report);
          },
        );
      case FieldNav.trip:
        return RouteScreen(
          phase: _tripPhase,
          postReroute: _postReroute,
          riskUpgraded: _riskUpgraded,
          isOffline: _isOffline,
          onPhaseChange: _setTripPhase,
          onRerouted: () => setState(() {
            _postReroute = true;
            _riskUpgraded = false;
            _tripPhase = TripPhase.active;
            _alertsBadge = 0;
          }),
          onNotNow: () => setState(() {
            _riskUpgraded = true;
            _tripPhase = TripPhase.active;
          }),
          onReport: () => _go(FieldNav.report),
        );
      case FieldNav.tasks:
        return MyTasksScreen(onBack: () => _go(FieldNav.dashboard));
      case FieldNav.report:
        return const ReportScreen();
      case FieldNav.route:
        return const RouteStatusScreen();
      case FieldNav.logistics:
        return const LogisticsScreen();
      case FieldNav.riders:
        return const LiveRidersScreen();
      case FieldNav.alerts:
        return AlertsScreen(
          onCriticalTap: _triggerRisk,
          onAlertsCleared: () => setState(() => _alertsBadge = 0),
        );
      case FieldNav.reports:
        return const ReportsScreen();
    }
  }
}
