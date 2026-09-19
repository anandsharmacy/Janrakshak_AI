import 'package:flutter/material.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// PriorityBadge — dot + label for task / incident severity.
class PriorityBadge extends StatelessWidget {
  final Priority level;

  const PriorityBadge({super.key, required this.level});

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
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: cfg.fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            cfg.label,
            style: AppTextStyles.chipLabel.copyWith(color: cfg.fg),
          ),
        ],
      ),
    );
  }

  _Cfg _cfg(Priority p) {
    switch (p) {
      case Priority.critical:
        return _Cfg(
          bg: AppColors.criticalBg,
          border: AppColors.signalRed700.withOpacity(0.4),
          fg: AppColors.signalRed700,
          label: 'Critical',
        );
      case Priority.high:
        return _Cfg(
          bg: AppColors.saffronBg,
          border: AppColors.saffron600.withOpacity(0.4),
          fg: AppColors.saffronDark,
          label: 'High',
        );
      case Priority.medium:
        return _Cfg(
          bg: AppColors.navyTint,
          border: AppColors.navy900.withOpacity(0.25),
          fg: AppColors.navy900,
          label: 'Medium',
        );
      case Priority.low:
        return _Cfg(
          bg: const Color(0xFFEEF1EC),
          border: AppColors.hairline,
          fg: AppColors.slate500,
          label: 'Low',
        );
    }
  }
}

class _Cfg {
  final Color bg, border, fg;
  final String label;
  const _Cfg({
    required this.bg,
    required this.border,
    required this.fg,
    required this.label,
  });
}
