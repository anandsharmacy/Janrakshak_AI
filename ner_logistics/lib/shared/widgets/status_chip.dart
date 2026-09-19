import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

enum ChipTone { critical, saffron, clear, navy, muted }

/// StatusChip — generic bordered label chip used across both tracks.
class StatusChip extends StatelessWidget {
  final ChipTone tone;
  final String label;
  final IconData? icon;

  const StatusChip({
    super.key,
    required this.tone,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg(tone);
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
          if (icon != null) ...[
            Icon(icon, size: 12, color: cfg.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.chipLabel.copyWith(color: cfg.fg),
          ),
        ],
      ),
    );
  }

  _Cfg _cfg(ChipTone t) {
    switch (t) {
      case ChipTone.critical:
        return _Cfg(
          bg: AppColors.criticalBg,
          border: AppColors.signalRed700.withOpacity(0.3),
          fg: AppColors.signalRed700,
        );
      case ChipTone.saffron:
        return _Cfg(
          bg: AppColors.saffronBg,
          border: AppColors.saffron600.withOpacity(0.3),
          fg: AppColors.saffronDark,
        );
      case ChipTone.clear:
        return _Cfg(
          bg: AppColors.clearBg,
          border: AppColors.deepGreen700.withOpacity(0.3),
          fg: AppColors.deepGreen700,
        );
      case ChipTone.navy:
        return _Cfg(
          bg: AppColors.navyTint,
          border: AppColors.navy900.withOpacity(0.25),
          fg: AppColors.navy900,
        );
      case ChipTone.muted:
        return _Cfg(
          bg: const Color(0xFFEEF1EC),
          border: AppColors.hairline,
          fg: AppColors.slate500,
        );
    }
  }
}

class _Cfg {
  final Color bg, border, fg;
  const _Cfg({required this.bg, required this.border, required this.fg});
}
