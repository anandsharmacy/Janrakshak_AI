import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// MapLegend — risk-on-segments color key.
/// Required on every screen that shows risk-colored map routes.
/// Color + icon + text — never color alone.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const rows = [
      _LegendRow(
        color: AppColors.deepGreen700,
        icon: Icons.check_circle_outline,
        label: 'Clear',
        dashed: false,
      ),
      _LegendRow(
        color: AppColors.saffron600,
        icon: Icons.warning_amber_outlined,
        label: 'Caution',
        dashed: false,
      ),
      _LegendRow(
        color: AppColors.signalRed700,
        icon: Icons.warning_outlined,
        label: 'High risk',
        dashed: false,
      ),
      _LegendRow(
        color: Color(0xFF9AA0A8),
        icon: null,
        label: 'Avoided route',
        dashed: true,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Risk on segments',
            style: AppTextStyles.cardTitle.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final row in rows) ...[
            _LegendRowWidget(row: row),
            if (row != rows.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _LegendRow {
  final Color color;
  final IconData? icon;
  final String label;
  final bool dashed;

  const _LegendRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.dashed,
  });
}

class _LegendRowWidget extends StatelessWidget {
  final _LegendRow row;
  const _LegendRowWidget({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Line segment (solid or dashed)
        SizedBox(
          width: 20,
          height: 3,
          child: row.dashed
              ? CustomPaint(painter: _DashPainter(color: row.color))
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: row.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
        ),
        const SizedBox(width: 6),
        // Icon (or spacer for dashed)
        SizedBox(
          width: 14,
          child: row.icon != null
              ? Icon(row.icon, size: 13, color: row.color)
              : null,
        ),
        const SizedBox(width: 4),
        Text(row.label, style: AppTextStyles.bodySmall),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset((x + 4).clamp(0, size.width), size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// DistrictMapLegend — 6-row legend used in the District Officer map screen.
class DistrictMapLegend extends StatelessWidget {
  const DistrictMapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final rows = [
      (AppColors.deepGreen700,  'Open Route',       false),
      (AppColors.saffron600,    'Restricted',        false),
      (AppColors.signalRed700,  'Closed / Blocked',  false),
      (AppColors.signalRed700,  'Critical Incident', false),
      (AppColors.saffron600,    'Active Incident',   false),
      (AppColors.navy900,       'Safe Zone',         true),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Legend',
              style: AppTextStyles.cardTitle.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 8,
            childAspectRatio: 5,
            children: rows.map((r) {
              return Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: r.$3
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: r.$1, width: 2),
                          )
                        : BoxDecoration(
                            color: r.$1,
                            shape: BoxShape.circle,
                          ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(r.$2,
                        style: AppTextStyles.caption,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
