import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo/demo_mode.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// Compact "Demo data" on/off switch for the navy [AppHeader].
class DemoToggle extends ConsumerWidget {
  const DemoToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(demoModeProvider);
    return Semantics(
      button: true,
      toggled: on,
      label: 'Demo data',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(demoModeProvider.notifier).set(!on),
        child: Container(
          height: 24,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            color: on ? AppColors.gold.withValues(alpha: 0.18) : Colors.white10,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.gold : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                on ? 'DEMO ON' : 'DEMO OFF',
                style: AppTextStyles.eyebrow.copyWith(
                  color: on ? AppColors.gold : Colors.white70,
                  fontSize: 9,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 14,
                padding: const EdgeInsets.all(2),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: on ? AppColors.gold : Colors.white24,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
