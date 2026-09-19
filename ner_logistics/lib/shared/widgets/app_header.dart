import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'demo_toggle.dart';

/// AppHeader — navy chrome top bar used across all three role tracks.
/// Mirrors the React FieldHeader / DistrictOfficerApp / ControlRoomApp top bar.
///
/// Layout:
///   Row 1: status-bar time  ·  signal/wifi/battery glyphs
///   Row 2: menu button  ·  title + subtitle  ·  bell (with badge)  ·  role avatar
class AppHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final String roleInitials;
  final Color roleAccent;
  final int alertCount;
  final bool isOffline;
  final VoidCallback onMenu;
  final VoidCallback onBell;
  final VoidCallback onAvatar;
  /// Optional second tap target on the subtitle (used to trigger demo risk event)
  final GestureTapCallback? onSubtitleDoubleTap;

  const AppHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.time = '09:41',
    required this.roleInitials,
    this.roleAccent = AppColors.gold,
    this.alertCount = 0,
    this.isOffline = false,
    required this.onMenu,
    required this.onBell,
    required this.onAvatar,
    this.onSubtitleDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy900,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status bar row ──────────────────────────────────
              Row(
                children: [
                  Text(time, style: AppTextStyles.statusBarTime),
                  const SizedBox(width: 10),
                  const DemoToggle(),
                  const Spacer(),
                  _SignalIcon(),
                  const SizedBox(width: 6),
                  isOffline
                      ? const Icon(Icons.wifi_off_outlined,
                          size: 17, color: Colors.white60)
                      : _WifiIcon(),
                  const SizedBox(width: 6),
                  _BatteryIcon(),
                ],
              ),
              const SizedBox(height: 10),
              // ── Navigation row ──────────────────────────────────
              Row(
                children: [
                  // Hamburger
                  _HeaderButton(onTap: onMenu, child: const Icon(Icons.menu, size: 24)),
                  const SizedBox(width: 8),
                  // Title block
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.screenTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        GestureDetector(
                          onDoubleTap: onSubtitleDoubleTap,
                          child: Text(
                            subtitle,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Bell with badge
                  _HeaderButton(
                    onTap: onBell,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.notifications_outlined, size: 21),
                        if (alertCount > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              height: 17,
                              constraints: const BoxConstraints(minWidth: 17),
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$alertCount',
                                style: AppTextStyles.eyebrow.copyWith(
                                  color: AppColors.navy900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Role avatar circle
                  GestureDetector(
                    onTap: onAvatar,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: roleAccent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        roleInitials,
                        style: AppTextStyles.eyebrowMd.copyWith(
                          color: AppColors.navy900,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
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
}

class _HeaderButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _HeaderButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: Colors.white12,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white, size: 22),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Static status-bar glyphs ─────────────────────────────────────────────────

class _SignalIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in [4.0, 7.0, 10.0, 13.0])
          Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.only(right: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(0.5),
            ),
          ),
      ],
    );
  }
}

class _WifiIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.wifi, size: 17, color: Colors.white70);
  }
}

class _BatteryIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.battery_full, size: 17, color: Colors.white70);
  }
}
