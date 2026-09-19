import 'package:flutter/material.dart';
import '../../theme/text_styles.dart';

/// SectionTitle — bold section heading with optional right-side action widget.
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const SectionTitle({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: AppTextStyles.sectionTitle),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
