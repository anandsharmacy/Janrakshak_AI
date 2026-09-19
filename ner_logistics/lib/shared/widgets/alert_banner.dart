import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

enum BannerTone { critical, caution, clear }

/// AlertBanner — inline severity banner used within screens.
/// Not a full-screen overlay; sits inline in the scroll body.
class AlertBanner extends StatelessWidget {
  final BannerTone tone;
  final String title;
  final String text;

  const AlertBanner({
    super.key,
    required this.tone,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cfg.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cfg.icon, size: 18, color: cfg.iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.cardTitle.copyWith(
                    color: cfg.titleColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.navy900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _Cfg _cfg(BannerTone t) {
    switch (t) {
      case BannerTone.critical:
        return _Cfg(
          bg: AppColors.criticalBg,
          border: AppColors.signalRed700.withOpacity(0.4),
          icon: Icons.warning_outlined,
          iconColor: AppColors.signalRed700,
          titleColor: AppColors.signalRed700,
        );
      case BannerTone.caution:
        return _Cfg(
          bg: AppColors.saffronBg,
          border: AppColors.saffron600.withOpacity(0.4),
          icon: Icons.warning_amber_outlined,
          iconColor: AppColors.saffron600,
          titleColor: AppColors.saffronDark,
        );
      case BannerTone.clear:
        return _Cfg(
          bg: AppColors.clearBg,
          border: AppColors.deepGreen700.withOpacity(0.4),
          icon: Icons.check_circle_outline,
          iconColor: AppColors.deepGreen700,
          titleColor: AppColors.deepGreen700,
        );
    }
  }
}

class _Cfg {
  final Color bg, border, iconColor, titleColor;
  final IconData icon;
  const _Cfg({
    required this.bg,
    required this.border,
    required this.icon,
    required this.iconColor,
    required this.titleColor,
  });
}
