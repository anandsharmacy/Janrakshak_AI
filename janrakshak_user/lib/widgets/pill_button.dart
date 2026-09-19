import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Filled = primary (accent by default), outlined = secondary.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color = AppColors.accent,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined, expand;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder();
    const size = Size(48, 48);
    final child = Text(label, style: const TextStyle(fontWeight: FontWeight.w700));
    final button = outlined
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon == null ? const SizedBox.shrink() : Icon(icon),
            label: child,
            style: OutlinedButton.styleFrom(
                shape: shape, minimumSize: size, foregroundColor: color, side: BorderSide(color: color, width: 1.5)),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            icon: icon == null ? const SizedBox.shrink() : Icon(icon),
            label: child,
            style: FilledButton.styleFrom(
              shape: shape,
              minimumSize: size,
              backgroundColor: color,
              foregroundColor: color == AppColors.accent ? AppColors.bgDark : AppColors.textOnDark,
            ),
          );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
