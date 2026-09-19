import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'card_surface.dart';

enum KpiTone { navy, critical, saffron, clear }

/// KpiTile — large numeric value + label used in 2-column dashboard grids.
class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final KpiTone tone;
  final String? hint;
  final VoidCallback? onTap;

  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.tone = KpiTone.navy,
    this.hint,
    this.onTap,
  });

  Color get _valueColor {
    switch (tone) {
      case KpiTone.navy:
        return AppColors.navy900;
      case KpiTone.critical:
        return AppColors.signalRed700;
      case KpiTone.saffron:
        return AppColors.saffron600;
      case KpiTone.clear:
        return AppColors.deepGreen700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.slate500,
                    height: 1.3,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: AppColors.slate500.withOpacity(0.5),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.kpiValue.copyWith(color: _valueColor),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.slate500.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
