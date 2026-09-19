import 'package:flutter/material.dart';
import '../../mock_data/mock_officers.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../shared/widgets/profile_summary.dart';

/// District Officer nav destinations — matches React DistrictOfficerApp NAV array.
enum DistrictNav {
  overview,
  map,
  incidents,
  routes,
  logistics,
  riders,
  tasks,
  ai,
  alerts,
  reports,
  analytics,
}

extension DistrictNavExt on DistrictNav {
  String get label {
    switch (this) {
      case DistrictNav.overview:   return 'Dashboard';
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

  IconData get icon {
    switch (this) {
      case DistrictNav.overview:   return Icons.home_outlined;
      case DistrictNav.map:        return Icons.map_outlined;
      case DistrictNav.incidents:  return Icons.warning_amber_outlined;
      case DistrictNav.routes:     return Icons.alt_route_outlined;
      case DistrictNav.logistics:  return Icons.local_shipping_outlined;
      case DistrictNav.riders:     return Icons.share_location_outlined;
      case DistrictNav.tasks:      return Icons.check_box_outlined;
      case DistrictNav.ai:         return Icons.auto_awesome_outlined;
      case DistrictNav.alerts:     return Icons.notifications_outlined;
      case DistrictNav.reports:    return Icons.description_outlined;
      case DistrictNav.analytics:  return Icons.bar_chart_outlined;
    }
  }

  int? badgeCount(int incidentBadge, int alertBadge) {
    if (this == DistrictNav.incidents) return incidentBadge > 0 ? incidentBadge : null;
    if (this == DistrictNav.alerts) return alertBadge > 0 ? alertBadge : null;
    return null;
  }
}

/// DistrictDrawer — slide-in navy drawer for the District Officer track.
class DistrictDrawer extends StatelessWidget {
  final DistrictNav current;
  final int incidentBadge;
  final int alertBadge;
  final Officer? officer;
  final ValueChanged<DistrictNav> onNavigate;
  final VoidCallback onClose;
  final VoidCallback onSignOut;

  const DistrictDrawer({
    super.key,
    required this.current,
    this.officer,
    this.incidentBadge = 2,
    this.alertBadge = 3,
    required this.onNavigate,
    required this.onClose,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: Colors.black.withOpacity(0.50),
        child: Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: MediaQuery.of(context).size.width * 0.82,
              constraints: const BoxConstraints(maxWidth: 310),
              height: double.infinity,
              color: AppColors.navy900,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Close button row
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 20),
                        onPressed: onClose,
                        padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
                      ),
                    ),
                    ProfileSummary(officer: officer ?? districtOfficer),
                    Divider(
                        color: Colors.white.withOpacity(0.1),
                        height: 1,
                        thickness: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(
                        'MAIN MENU',
                        style: AppTextStyles.eyebrow.copyWith(
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        children: [
                          for (final nav in DistrictNav.values)
                            _NavRow(
                              label: nav.label,
                              icon: nav.icon,
                              isActive: current == nav,
                              badge: nav.badgeCount(incidentBadge, alertBadge),
                              onTap: () {
                                onNavigate(nav);
                                onClose();
                              },
                            ),
                          const SizedBox(height: 12),
                          Divider(
                              color: Colors.white.withOpacity(0.1),
                              height: 1),
                          const SizedBox(height: 8),
                          _NavRow(
                            label: 'Sign out',
                            icon: Icons.logout_outlined,
                            isActive: false,
                            onTap: onSignOut,
                            muted: true,
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

class _NavRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;
  final bool muted;

  const _NavRow({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.badge,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = muted
        ? Colors.white54
        : isActive
            ? Colors.white
            : Colors.white70;
    final iconFg = muted
        ? Colors.white54
        : isActive
            ? AppColors.gold
            : Colors.white70;

    return Stack(
      children: [
        Material(
          color: isActive ? Colors.white.withOpacity(0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.white12,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: iconFg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.buttonSmall.copyWith(
                        color: fg,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Container(
                      height: 20,
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: AppColors.signalRed700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$badge',
                        style: AppTextStyles.eyebrow.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Gold left accent for active item
        if (isActive)
          Positioned(
            left: 0,
            top: 6,
            bottom: 6,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
