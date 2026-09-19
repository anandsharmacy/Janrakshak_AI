import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// ScrollTabs — horizontal pill-style scroll tab bar.
/// Used in district officer incident/route screens.
class ScrollTabs<T> extends StatelessWidget {
  final List<ScrollTab<T>> tabs;
  final T active;
  final ValueChanged<T> onChange;

  const ScrollTabs({
    super.key,
    required this.tabs,
    required this.active,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final on = tab.id == active;
          return GestureDetector(
            onTap: () => onChange(tab.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: on ? AppColors.navy900 : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: on ? AppColors.navy900 : AppColors.hairline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab.label,
                    style: AppTextStyles.tabLabel.copyWith(
                      color: on ? Colors.white : AppColors.slate500,
                    ),
                  ),
                  if (tab.count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${tab.count}',
                      style: AppTextStyles.caption.copyWith(
                        color: on
                            ? Colors.white.withOpacity(0.7)
                            : AppColors.slate500.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ScrollTab<T> {
  final T id;
  final String label;
  final int? count;
  const ScrollTab({required this.id, required this.label, this.count});
}
