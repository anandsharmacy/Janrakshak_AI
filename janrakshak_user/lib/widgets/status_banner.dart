import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bold lead-in + explanatory text; used for every degraded state.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.lead,
    required this.text,
    this.color = AppColors.statusModerate,
    this.icon = Icons.info_outline,
  });
  final String lead, text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          border: Border(left: BorderSide(color: color, width: 4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$lead ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: text),
            ])),
          ),
        ]),
      );
}
