import 'package:flutter/material.dart';
import '../../../mock_data/mock_officers.dart';
import '../../../mock_data/mock_routes.dart';
import '../../../mock_data/mock_tasks.dart';
import '../../../mock_data/models.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

/// FieldDashboard — matches React FieldDashboard exactly.
/// KPI 2×2 grid · area situation card · priority tasks · nearby incidents
/// · quick-action grid.
class FieldDashboard extends StatelessWidget {
  final bool isOffline;
  final Officer? officer;
  final VoidCallback onToggleOffline;
  final VoidCallback onStartTask;
  final VoidCallback onOpenTasks;
  final VoidCallback onViewIncidents;
  final ValueChanged<IncidentType> onReportType;

  const FieldDashboard({
    super.key,
    required this.isOffline,
    this.officer,
    required this.onToggleOffline,
    required this.onStartTask,
    required this.onOpenTasks,
    required this.onViewIncidents,
    required this.onReportType,
  });

  static const _quickActions = [
    (type: IncidentType.flood, label: 'Flood', emoji: '🌊'),
    (type: IncidentType.roadBlockage, label: 'Road Blockage', emoji: '🚧'),
    (type: IncidentType.landslide, label: 'Landslide', emoji: '⛰️'),
    (type: IncidentType.accident, label: 'Accident', emoji: '🚗'),
    (type: IncidentType.infraDamage, label: 'Infrastructure Damage', emoji: '🏗️'),
  ];

  @override
  Widget build(BuildContext context) {
    final tasks = buildMockTasks()
        .where((t) =>
            t.priority == Priority.critical ||
            t.priority == Priority.high)
        .take(3)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI grid ─────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              KpiTile(
                label: 'Assigned Tasks',
                value: '8',
                tone: KpiTone.navy,
                onTap: onOpenTasks,
              ),
              KpiTile(
                label: 'Pending Tasks',
                value: '3',
                tone: KpiTone.saffron,
                onTap: onOpenTasks,
              ),
              KpiTile(
                label: 'Active Incidents',
                value: '2',
                tone: KpiTone.navy,
                onTap: onViewIncidents,
              ),
              KpiTile(
                label: 'Critical Alerts',
                value: '1',
                tone: KpiTone.critical,
                onTap: onViewIncidents,
              ),
            ],
          ),

          // ── Current Area Situation ────────────────────────────
          SectionTitle(title: 'Current Area Situation'),
          CardSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 15,
                                  color: AppColors.slate500),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  (officer ?? fieldOfficer).region,
                                  style: AppTextStyles.cardTitle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Monitored sector · ${(officer ?? fieldOfficer).officerId}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    const RiskBadge(level: RiskLevel.critical),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Accessibility Score',
                        style: AppTextStyles.captionSemibold.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy900,
                        ),
                      ),
                    ),
                    Text(
                      '72/100 · Fair',
                      style: AppTextStyles.captionSemibold.copyWith(
                        color: AppColors.saffron600,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 0.72,
                    backgroundColor:
                        AppColors.slate500.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.saffron600),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.hairline, height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Risk level',
                              style: AppTextStyles.caption),
                          Text('High',
                              style: AppTextStyles.cardTitle.copyWith(
                                  color: AppColors.signalRed700,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nearby incidents',
                              style: AppTextStyles.caption),
                          Text('2 within 5 km',
                              style: AppTextStyles.cardTitle),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Last updated 2 min ago · DEMO DATA',
                  style: AppTextStyles.disclaimer,
                ),
              ],
            ),
          ),

          // ── My Priority Tasks ─────────────────────────────────
          SectionTitle(
            title: 'My Priority Tasks',
            action: TextButton(
              onPressed: onOpenTasks,
              child: const Text('View all'),
            ),
          ),
          Column(
            children: tasks.map((t) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CardSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(t.id,
                                    style: AppTextStyles.caption
                                        .copyWith(
                                            color: AppColors.slate500
                                                .withOpacity(0.7))),
                                const SizedBox(height: 2),
                                Text(t.title,
                                    style: AppTextStyles.cardTitle
                                        .copyWith(
                                            fontWeight:
                                                FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          PriorityBadge(level: t.priority),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14,
                              color: AppColors.slate500
                                  .withOpacity(0.7)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(t.location,
                                style: AppTextStyles.bodySmall),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          StatusChip(
                            tone: ChipTone.muted,
                            label: 'Due ${t.dueTime}',
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: onStartTask,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              minimumSize: Size.zero,
                              textStyle: AppTextStyles.buttonSmall,
                            ),
                            child: const Text('Start Task'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Nearby Incidents ──────────────────────────────────
          SectionTitle(
            title: 'Nearby Incidents',
            action: TextButton(
              onPressed: onViewIncidents,
              child: const Text('View All Incidents'),
            ),
          ),
          CardSurface(
            child: Column(
              children: mockNearbyIncidents
                  .asMap()
                  .entries
                  .map((e) {
                final n = e.value;
                final isFirst = e.key == 0;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: isFirst
                        ? null
                        : Border(
                            top: BorderSide(
                                color: AppColors.hairline)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        n.level == RiskLevel.clear
                            ? Icons.check_circle_outline
                            : Icons.warning_outlined,
                        size: 18,
                        color: n.level == RiskLevel.clear
                            ? AppColors.deepGreen700
                            : n.level == RiskLevel.caution
                                ? AppColors.saffron600
                                : AppColors.signalRed700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(n.title,
                                style:
                                    AppTextStyles.cardTitle),
                            const SizedBox(height: 2),
                            Text(n.place,
                                style:
                                    AppTextStyles.bodySmall),
                          ],
                        ),
                      ),
                      Text(
                        n.distance,
                        style: AppTextStyles.captionSemibold
                            .copyWith(
                                color: AppColors.slate500
                                    .withOpacity(0.7),
                                fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Quick Actions ─────────────────────────────────────
          const SectionTitle(title: 'Quick Actions'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: _quickActions.asMap().entries.map((e) {
              final q = e.value;
              final isLast = e.key == _quickActions.length - 1;
              // Last item spans full width via layout trick below
              return CardSurface(
                onTap: () => onReportType(q.type),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Text(q.emoji,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Report ${q.label}',
                        style: AppTextStyles.captionSemibold
                            .copyWith(
                                color: AppColors.navy900,
                                fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color:
                            AppColors.gold.withOpacity(0.13),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add,
                          size: 14, color: AppColors.gold),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
