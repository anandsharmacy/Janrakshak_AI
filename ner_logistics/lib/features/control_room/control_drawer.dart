import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// Control Room nav destinations — matches React ControlRoomApp NAV array.
enum ControlNav {
  command,
  map,
  logistics,
  riders,
  incidents,
  routes,
  ai,
  alerts,
  analytics,
}

extension ControlNavExt on ControlNav {
  String get label {
    switch (this) {
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

  IconData get icon {
    switch (this) {
      case ControlNav.command:    return Icons.home_outlined;
      case ControlNav.map:        return Icons.map_outlined;
      case ControlNav.logistics:  return Icons.local_shipping_outlined;
      case ControlNav.riders:     return Icons.share_location_outlined;
      case ControlNav.incidents:  return Icons.warning_amber_outlined;
      case ControlNav.routes:     return Icons.alt_route_outlined;
      case ControlNav.ai:         return Icons.auto_awesome_outlined;
      case ControlNav.alerts:     return Icons.notifications_outlined;
      case ControlNav.analytics:  return Icons.bar_chart_outlined;
    }
  }
}

/// ControlDrawer — slide-in navy drawer for the Control Room track.
class ControlDrawer extends StatelessWidget {
  final ControlNav current;
  final int alertBadge;
  final ValueChanged<ControlNav> onNavigate;
  final VoidCallback onClose;
  final VoidCallback onSignOut;

  const ControlDrawer({
    super.key,
    required this.current,
    this.alertBadge = 5,
    required this.onNavigate,
    required this.onClose,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: ColoredBox(
        color: Colors.black.withOpacity(0.40),
        child: Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: MediaQuery.of(context).size.width * 0.80,
              constraints: const BoxConstraints(maxWidth: 300),
              height: double.infinity,
              color: AppColors.navy900,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: CO badge + title + close
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 12, 0),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'CO',
                              style: AppTextStyles.eyebrowMd.copyWith(
                                color: AppColors.navy900,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Control Officer',
                                  style: AppTextStyles.cardTitle
                                      .copyWith(color: Colors.white),
                                ),
                                Text(
                                  'NER Regional Command',
                                  style: AppTextStyles.caption
                                      .copyWith(color: Colors.white60),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white70, size: 20),
                            onPressed: onClose,
                          ),
                        ],
                      ),
                    ),
                    // Scope block
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: Colors.white.withOpacity(0.12))),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REGIONAL CONTROL',
                            style: AppTextStyles.eyebrow.copyWith(
                              color: Colors.white.withOpacity(0.50),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'North Eastern Region · 8 states',
                            style: AppTextStyles.bodySmallMedium.copyWith(
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.systemOnline,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'System Online',
                                style: AppTextStyles.caption
                                    .copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(
                        'MAIN MENU',
                        style: AppTextStyles.eyebrow.copyWith(
                          color: Colors.white.withOpacity(0.40),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        children: [
                          for (final nav in ControlNav.values)
                            _ControlNavRow(
                              label: nav.label,
                              icon: nav.icon,
                              isActive: current == nav,
                              badge: nav == ControlNav.alerts && alertBadge > 0
                                  ? alertBadge
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
                          _ControlNavRow(
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

class _ControlNavRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;
  final bool muted;

  const _ControlNavRow({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.badge,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = muted
        ? Colors.white54
        : isActive
            ? AppColors.gold
            : Colors.white70;
    final textColor = muted
        ? Colors.white54
        : isActive
            ? Colors.white
            : Colors.white.withOpacity(0.85);

    return Stack(
      children: [
        Material(
          color: isActive ? Colors.white.withOpacity(0.10) : Colors.transparent,
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
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.buttonSmall.copyWith(
                        color: textColor,
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
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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
