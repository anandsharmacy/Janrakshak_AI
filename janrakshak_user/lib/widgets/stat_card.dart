import 'package:flutter/material.dart';

import 'panel.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.icon, required this.value, required this.label, this.onTap});
  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LightCard(
      onTap: onTap,
      child: Builder(builder: (context) {
        final t = Theme.of(context).textTheme; // on-light text theme
        return Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(value, style: t.headlineLarge),
              Text(label, style: t.bodySmall),
            ],
          ),
        );
      }),
    );
  }
}
