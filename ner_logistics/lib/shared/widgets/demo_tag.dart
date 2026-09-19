import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// DemoTag — small "Demo data" indicator required on every mock data screen.
class DemoTag extends StatelessWidget {
  const DemoTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        'DEMO DATA',
        style: AppTextStyles.eyebrow.copyWith(
          color: AppColors.slate500.withOpacity(0.7),
        ),
      ),
    );
  }
}
