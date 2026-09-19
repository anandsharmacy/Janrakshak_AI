import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tracked-out uppercase caption ("ACTIVE REGION", "MAIN MENU").
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall);
}

/// bgLight card; everything inside gets dark-on-light text and icons.
class LightCard extends StatelessWidget {
  const LightCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.onLight(Theme.of(context)),
        child: Material(
          color: AppColors.bgLight,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}
