import 'package:flutter/material.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// RiskBadge — color + icon + text always together.
/// Never use color alone for risk indication.
class RiskBadge extends StatelessWidget {
  final RiskLevel level;
  final bool compact;

  const RiskBadge({super.key, required this.level, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cfg.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cfg.icon, size: compact ? 11 : 13, color: cfg.fg),
          const SizedBox(width: 4),
          Text(
            cfg.label,
            style: AppTextStyles.chipLabel.copyWith(color: cfg.fg),
          ),
        ],
      ),
    );
  }

  _RiskCfg _cfg(RiskLevel level) {
    switch (level) {
      case RiskLevel.clear:
        return _RiskCfg(
          bg: AppColors.clearBg,
          border: AppColors.deepGreen700.withOpacity(0.3),
          fg: AppColors.deepGreen700,
          icon: Icons.check_circle_outline,
          label: 'Clear',
        );
      case RiskLevel.caution:
        return _RiskCfg(
          bg: AppColors.saffronBg,
          border: AppColors.saffron600.withOpacity(0.3),
          fg: AppColors.saffronDark,
          icon: Icons.warning_amber_outlined,
          label: 'Caution',
        );
      case RiskLevel.critical:
        return _RiskCfg(
          bg: AppColors.criticalBg,
          border: AppColors.signalRed700.withOpacity(0.3),
          fg: AppColors.signalRed700,
          icon: Icons.warning_outlined,
          label: 'High risk',
        );
    }
  }
}

class _RiskCfg {
  final Color bg, border, fg;
  final IconData icon;
  final String label;
  const _RiskCfg({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
    required this.label,
  });
}
