import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'map_state.dart';

class StatusSheet extends ConsumerWidget {
  const StatusSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(mapSelectionProvider);
    final m = ref.watch(areaMetricsProvider);
    if (place == null || m == null) return const SizedBox.shrink();
    final range = ref.watch(mapRangeProvider);
    final live = range == MapRange.live;
    final title = place.district ?? place.name ?? 'Selected location';
    final where = [if (place.district != null && place.state != null) place.state!, if (place.region != null) '${place.region} region'].join(' · ');

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.14,
      maxChildSize: 0.88,
      snap: true,
      builder: (context, scroll) => Theme(
        data: AppTheme.onLight(Theme.of(context)),
        child: Builder(builder: (context) {
          final t = Theme.of(context).textTheme;
          return Material(
            color: AppColors.bgLight,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            clipBehavior: Clip.antiAlias,
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              Center(
                child: Container(
                    width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: AppColors.textOnLight.withAlpha(60), borderRadius: BorderRadius.circular(2))),
              ),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Eyebrow('Selected area'),
                    Text(title, style: t.headlineSmall),
                    if (where.isNotEmpty) Text(where, style: t.bodyMedium),
                  ]),
                ),
                IconButton(
                    tooltip: 'Close', icon: const Icon(Icons.close_outlined), onPressed: ref.read(mapSelectionProvider.notifier).clear),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Text('${m.risk.value.round()}/100', style: t.headlineMedium),
                const SizedBox(width: 8),
                const Text('—'),
                const SizedBox(width: 8),
                SeverityIndicator(m.riskSeverity),
                const Spacer(),
                Text('Risk score', style: t.labelMedium),
              ]),
              if (!live)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Averages for the last ${range.days} days from user reports and Field Officer verifications. Sparklines show the trend.',
                      style: t.bodySmall),
                ),
              const Divider(height: 24),
              _MetricRow(Icons.groups_outlined, 'Population affected', m.population, live, (v) => _fmt(v)),
              _MetricRow(Icons.water_drop_outlined, 'Rainfall', m.rainfall, live, (v) => '${v.toStringAsFixed(1)} mm'),
              if (m.wave != null) _MetricRow(Icons.waves_outlined, 'Wave height', m.wave!, live, (v) => '${v.toStringAsFixed(1)} m'),
              _MetricRow(Icons.air_outlined, 'Wind speed', m.wind, live, (v) => '${v.toStringAsFixed(0)} km/h'),
              const Divider(height: 24),
              _Facilities(Icons.local_hospital_outlined, 'Hospitals', m.hospitals),
              _Facilities(Icons.night_shelter_outlined, 'Shelters', m.shelters),
            ]),
          );
        }),
      ),
    );
  }

  static String _fmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);
}

class _MetricRow extends StatelessWidget {
  const _MetricRow(this.icon, this.label, this.metric, this.live, this.format);
  final IconData icon;
  final String label;
  final Metric metric;
  final bool live;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = metric.delta;
    final (trendIcon, trendText) = d.abs() < metric.value * 0.03
        ? (Icons.trending_flat_outlined, 'Steady')
        : d > 0
            ? (Icons.trending_up_outlined, 'Rising')
            : (Icons.trending_down_outlined, 'Falling');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.bodySmall),
            Text(format(metric.value), style: t.titleLarge),
          ]),
        ),
        if (!live) ...[
          SizedBox(width: 90, height: 32, child: _Sparkline(metric.series)),
          const SizedBox(width: 8),
          Semantics(
            label: '$label $trendText',
            excludeSemantics: true,
            child: Column(children: [Icon(trendIcon, size: 20), Text(trendText, style: t.labelSmall)]),
          ),
        ],
      ]),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline(this.series);
  final List<double> series;

  @override
  Widget build(BuildContext context) => LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i])],
            isCurved: true,
            color: AppColors.textOnLight,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ));
}

class _Facilities extends StatelessWidget {
  const _Facilities(this.icon, this.title, this.names);
  final IconData icon;
  final String title;
  final List<String> names;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon),
        title: Text('$title (${names.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
        children: [for (final n in names) ListTile(dense: true, contentPadding: const EdgeInsets.only(left: 40), title: Text(n))],
      );
}
