import 'package:flutter/material.dart';

import '../data/hazard.dart';
import '../data/taxonomy.dart';
import '../theme/app_theme.dart';
import 'panel.dart';
import 'severity_indicator.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class AlertCard extends StatelessWidget {
  const AlertCard(this.h, {super.key});
  final Hazard h;

  @override
  Widget build(BuildContext context) => LightCard(
        child: Builder(builder: (context) {
          final t = Theme.of(context).textTheme;
          final verified = h.source == ReportSource.fieldOfficer;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: h.severity.color, borderRadius: BorderRadius.circular(12)),
                child: Icon(incidentIcon(h.type), color: AppColors.textOnDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.type, style: t.titleLarge),
                  Text('${h.district}, ${h.state}', style: t.bodyMedium),
                ]),
              ),
              SeverityIndicator(h.severity),
            ]),
            const SizedBox(height: 10),
            Text(h.summary, style: t.bodyMedium),
            const SizedBox(height: 10),
            Row(children: [
              Icon(h.source.icon, size: 16, color: verified ? AppColors.statusOk : null),
              const SizedBox(width: 4),
              Flexible(
                child: Text(h.source.label,
                    style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: verified ? AppColors.statusOk : null)),
              ),
              const Spacer(),
              Text(timeAgo(h.at), style: t.labelMedium),
            ]),
          ]);
        }),
      );
}
