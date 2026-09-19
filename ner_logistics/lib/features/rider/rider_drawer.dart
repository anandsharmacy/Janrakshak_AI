import 'package:flutter/material.dart';
import '../../mock_data/mock_officers.dart';
import '../../mock_data/models.dart';
import '../../shared/widgets/profile_summary.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

enum RiderNav { dashboard, deliveries, trip, routeAlerts, report, history, queue }

extension RiderNavLabel on RiderNav {
  String get label {
    switch (this) {
      case RiderNav.dashboard:
        return 'Dashboard';
      case RiderNav.deliveries:
        return 'My Deliveries';
      case RiderNav.trip:
        return 'Active Trip';
      case RiderNav.routeAlerts:
        return 'Route & Alerts';
      case RiderNav.report:
        return 'Report Issue';
      case RiderNav.history:
        return 'Delivery History';
      case RiderNav.queue:
        return 'Offline Queue';
    }
  }

  IconData get icon {
    switch (this) {
      case RiderNav.dashboard:
        return Icons.home_outlined;
      case RiderNav.deliveries:
        return Icons.inventory_2_outlined;
      case RiderNav.trip:
        return Icons.navigation_outlined;
      case RiderNav.routeAlerts:
        return Icons.alt_route_outlined;
      case RiderNav.report:
        return Icons.report_problem_outlined;
      case RiderNav.history:
        return Icons.history_outlined;
      case RiderNav.queue:
        return Icons.sync_problem_outlined;
    }
  }
}

class RiderDrawer extends StatelessWidget {
  final RiderNav current;
  final int queueCount;
  final Officer? officer;
  final ValueChanged<RiderNav> onNavigate;
  final VoidCallback onClose;
  final VoidCallback onSignOut;

  const RiderDrawer({
    super.key,
    required this.current,
    required this.queueCount,
    this.officer,
    required this.onNavigate,
    required this.onClose,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: Colors.black.withOpacity(0.45),
        child: Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: MediaQuery.of(context).size.width * 0.84,
              constraints: const BoxConstraints(maxWidth: 300),
              height: double.infinity,
              color: AppColors.navy900,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileSummary(officer: officer ?? riderOfficer),
                    Divider(color: Colors.white.withOpacity(0.1), height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('RIDER WORKSPACE',
                          style: AppTextStyles.eyebrow.copyWith(
                              color: Colors.white.withOpacity(0.4))),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final nav in RiderNav.values)
                            _RiderDrawerRow(
                              nav: nav,
                              active: current == nav,
                              badge: nav == RiderNav.queue && queueCount > 0
                                  ? queueCount
                                  : null,
                              onTap: () {
                                onNavigate(nav);
                                onClose();
                              },
                            ),
                          const SizedBox(height: 12),
                          Divider(color: Colors.white.withOpacity(0.1)),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.logout_outlined,
                                color: Colors.white70, size: 20),
                            title: Text('Sign out',
                                style: AppTextStyles.bodySmallMedium.copyWith(
                                    color: Colors.white70)),
                            onTap: onSignOut,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RiderDrawerRow extends StatelessWidget {
  final RiderNav nav;
  final bool active;
  final int? badge;
  final VoidCallback onTap;

  const _RiderDrawerRow({
    required this.nav,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withOpacity(0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(nav.icon,
            color: active ? AppColors.gold : Colors.white70, size: 20),
        title: Text(nav.label,
            style: AppTextStyles.bodySmallMedium.copyWith(
                color: active ? Colors.white : Colors.white70,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        trailing: badge == null
            ? null
            : CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.gold,
                child: Text('$badge',
                    style: AppTextStyles.eyebrow.copyWith(
                        color: AppColors.navy900, fontSize: 10)),
              ),
        onTap: onTap,
      ),
    );
  }
}