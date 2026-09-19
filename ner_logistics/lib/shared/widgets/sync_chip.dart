import 'package:flutter/material.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// SyncChip — pending / synced / rejected offline-sync status indicator.
class SyncChip extends StatelessWidget {
  final SyncStatus status;

  const SyncChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg(status);
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
          Icon(cfg.icon, size: 13, color: cfg.fg),
          const SizedBox(width: 4),
          Text(
            cfg.label,
            style: AppTextStyles.chipLabel.copyWith(color: cfg.fg),
          ),
        ],
      ),
    );
  }

  _ChipCfg _cfg(SyncStatus s) {
    switch (s) {
      case SyncStatus.pending:
        return _ChipCfg(
          bg: AppColors.saffronBg,
          border: AppColors.saffron600.withOpacity(0.3),
          fg: AppColors.saffronDark,
          icon: Icons.access_time_outlined,
          label: 'Pending sync',
        );
      case SyncStatus.synced:
        return _ChipCfg(
          bg: AppColors.clearBg,
          border: AppColors.deepGreen700.withOpacity(0.3),
          fg: AppColors.deepGreen700,
          icon: Icons.check_circle_outline,
          label: 'Synced',
        );
      case SyncStatus.rejected:
        return _ChipCfg(
          bg: AppColors.criticalBg,
          border: AppColors.signalRed700.withOpacity(0.3),
          fg: AppColors.signalRed700,
          icon: Icons.cancel_outlined,
          label: 'Rejected',
        );
    }
  }
}

class _ChipCfg {
  final Color bg, border, fg;
  final IconData icon;
  final String label;
  const _ChipCfg({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
    required this.label,
  });
}
