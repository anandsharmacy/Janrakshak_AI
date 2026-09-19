import 'package:flutter/material.dart';
import '../../theme/colors.dart';

/// CardSurface — flat white card with 1px hairline border.
/// No elevation, no shadow — matches the government-document visual register.
class CardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double radius;
  final Color? backgroundColor;
  // Optional left accent bar (used for escalated incidents)
  final Color? leftAccentColor;

  const CardSurface({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.radius = 6,
    this.backgroundColor,
    this.leftAccentColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (leftAccentColor != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: leftAccentColor!),
            ),
          if (padding != null)
            Padding(padding: padding!, child: child)
          else
            child,
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          splashColor: AppColors.navy900.withOpacity(0.04),
          highlightColor: AppColors.navy900.withOpacity(0.02),
          child: card,
        ),
      );
    }
    return card;
  }
}
