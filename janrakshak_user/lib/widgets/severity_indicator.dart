import 'package:flutter/material.dart';

import '../data/taxonomy.dart';

/// Colored dot + text label; colour is never the only signal.
class SeverityIndicator extends StatelessWidget {
  const SeverityIndicator(this.severity, {super.key});
  final Severity severity;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Severity: ${severity.label}',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10, height: 10, decoration: BoxDecoration(color: severity.color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(severity.label,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color)),
        ]),
      );
}
