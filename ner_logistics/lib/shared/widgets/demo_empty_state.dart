import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// Placeholder for screens that only have sample data behind them.
class DemoEmptyState extends StatelessWidget {
  final String title;
  final IconData icon;

  const DemoEmptyState({
    super.key,
    required this.title,
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.slate500),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.cardTitle, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Demo data is off. Switch it on at the top of the screen to preview sample data.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A screen whose content is sample data: heading, any live widgets, then the
/// empty state. Shown instead of the sample content while demo data is off.
class DemoOffPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> live;

  const DemoOffPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.live = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.pageHeading),
        const SizedBox(height: 4),
        Text(subtitle, style: AppTextStyles.bodySmall),
        ...live,
        const SizedBox(height: 24),
        const DemoEmptyState(title: 'Nothing to show yet'),
      ],
    );
  }
}
