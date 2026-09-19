import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// AccessScoreBar — numeric accessibility score with colored progress bar.
/// Higher score = worse accessibility (district officer convention).
class AccessScoreBar extends StatelessWidget {
  final int score;
  final bool compact;

  const AccessScoreBar({super.key, required this.score, this.compact = false});

  Color get _barColor {
    if (score <= 25) return AppColors.deepGreen700;
    if (score <= 50) return AppColors.saffron600;
    return AppColors.signalRed700;
  }

  String get _bandLabel {
    if (score <= 25) return 'Good';
    if (score <= 50) return 'Moderate';
    if (score <= 75) return 'Restricted';
    return 'Critical';
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Text(
        '$score · $_bandLabel',
        style: AppTextStyles.cardTitle.copyWith(color: _barColor),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$score',
              style: AppTextStyles.statValue.copyWith(color: _barColor),
            ),
            Text(
              '/100',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(width: 6),
            Text(
              _bandLabel,
              style: AppTextStyles.cardTitle.copyWith(color: _barColor),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: AppColors.slate500.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(_barColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
