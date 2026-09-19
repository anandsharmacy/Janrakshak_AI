import 'package:flutter/material.dart';
import '../../mock_data/mock_officers.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../shared/widgets/profile_summary.dart';

/// Field Officer nav destinations — matches DRAWER_ITEMS in React source.
enum FieldNav {
  dashboard,
  trip,
  tasks,
  report,
  route,
  logistics,
  riders,
  alerts,
  reports,
}

extension FieldNavLabel on FieldNav {
  String get label {
    switch (this) {
      case FieldNav.dashboard:   return 'Dashboard';
      case FieldNav.trip:        return 'Active Trip';
      case FieldNav.tasks:       return 'My Tasks';
      case FieldNav.report:      return 'Report Incident';
      case FieldNav.route:       return 'Route Status';
      case FieldNav.logistics:   return 'Logistics';
      case FieldNav.riders:      return 'Live Riders';
      case FieldNav.alerts:      return 'Alerts';
      case FieldNav.reports:     return 'Reports';
    }
  }

  IconData get icon {
    switch (this) {
      case FieldNav.dashboard:   return Icons.home_outlined;
      case FieldNav.trip:        return Icons.navigation_outlined;
      case FieldNav.tasks:       return Icons.check_box_outlined;
      case FieldNav.report:      return Icons.description_outlined;
      case FieldNav.route:       return Icons.alt_route_outlined;
      case FieldNav.logistics:   return Icons.local_shipping_outlined;
      case FieldNav.riders:      return Icons.share_location_outlined;
      case FieldNav.alerts:      return Icons.notifications_outlined;
      case FieldNav.reports:     return Icons.folder_outlined;
    }
  }
}

/// FieldDrawer — slide-in navy sidebar for the Field Officer track.
/// Gold active indicator + identity block matches React FieldDrawer exactly.
class FieldDrawer extends StatelessWidget {
  final FieldNav current;
  final int alertCount;
  final Officer? officer;
  final ValueChanged<FieldNav> onNavigate;
  final VoidCallback onClose;
  final VoidCallback onSignOut;

  const FieldDrawer({
    super.key,
    required this.current,
    required this.alertCount,
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
            onTap: () {}, // absorb taps inside the drawer
            child: Container(
              width: MediaQuery.of(context).size.width * 0.82,
              constraints: const BoxConstraints(maxWidth: 300),
              height: double.infinity,
              color: AppColors.navy900,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Identity block
                    ProfileSummary(officer: officer ?? fieldOfficer),
                    // Divider
                    Divider(
                        color: Colors.white.withOpacity(0.1),
                        height: 1,
                        thickness: 1),
                    // Main menu label
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'MAIN MENU',
                        style: AppTextStyles.eyebrow.copyWith(
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),
                    // Nav items
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        children: [
                          for (final nav in FieldNav.values)
                            _DrawerRow(
                              nav: nav,
                              isActive: current == nav,
                              badge: nav == FieldNav.alerts && alertCount > 0
                                  ? alertCount
                                  : null,
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
                          // Sign out row
                          _SignOutRow(onSignOut: onSignOut),
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

class _DrawerRow extends StatelessWidget {
  final FieldNav nav;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;

  const _DrawerRow({
    required this.nav,
    required this.isActive,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? Colors.white.withOpacity(0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.white12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Gold left bar when active
              if (isActive)
                Positioned(
                  left: 0,
                  child: Container(
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Icon(
                nav.icon,
                size: 20,
                color: isActive ? AppColors.gold : Colors.white70,
                weight: isActive ? 700 : 400,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nav.label,
                  style: AppTextStyles.buttonSmall.copyWith(
                    color: isActive ? Colors.white : Colors.white70,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  height: 20,
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$badge',
                    style: AppTextStyles.eyebrow.copyWith(
                      color: AppColors.navy900,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignOutRow extends StatelessWidget {
  final VoidCallback onSignOut;
  const _SignOutRow({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onSignOut,
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.white12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.logout_outlined,
                  size: 20, color: Colors.white54),
              const SizedBox(width: 12),
              Text(
                'Sign out',
                style: AppTextStyles.buttonSmall.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
