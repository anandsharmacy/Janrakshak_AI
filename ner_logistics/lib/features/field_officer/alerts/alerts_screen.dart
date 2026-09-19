import 'package:flutter/material.dart';
import '../../../mock_data/mock_alerts.dart';
import '../../../mock_data/models.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

class AlertsScreen extends StatefulWidget {
  final VoidCallback? onCriticalTap;
  final VoidCallback? onAlertsCleared;

  const AlertsScreen({
    super.key,
    this.onCriticalTap,
    this.onAlertsCleared,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertSeverity _tab = AlertSeverity.critical;
  final Map<String, String> _ackState = {}; // id → 'idle'|'loading'|'done'

  List<AppAlert> get _filtered =>
      mockAlerts.where((a) => a.severity == _tab).toList();

  String _getAck(String id) => _ackState[id] ?? 'idle';

  Future<void> _acknowledge(String id) async {
    setState(() => _ackState[id] = 'loading');
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _ackState[id] = 'done');
  }

  static const _tabs = [
    (AlertSeverity.critical,  'Critical'),
    (AlertSeverity.high,      'High'),
    (AlertSeverity.moderate,  'Moderate'),
    (AlertSeverity.info,      'Info'),
  ];

  int _tabCount(AlertSeverity s) =>
      mockAlerts.where((a) => a.severity == s).length;

  Color _tabBadgeColor(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.critical: return AppColors.signalRed700;
      case AlertSeverity.high:     return AppColors.saffron600;
      case AlertSeverity.moderate: return AppColors.navy900;
      case AlertSeverity.info:     return AppColors.slate500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          color: Colors.white,
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: _tabs.map((t) {
                    final active = _tab == t.$1;
                    final count = _tabCount(t.$1);
                    return GestureDetector(
                      onTap: () => setState(() => _tab = t.$1),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                            12, 10, 12, 10),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: active
                                  ? AppColors.navy900
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              t.$2,
                              style: AppTextStyles.tabLabel.copyWith(
                                color: active
                                    ? AppColors.navy900
                                    : AppColors.slate500,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _tabBadgeColor(t.$1)
                                      .withOpacity(
                                          active ? 1 : 0.15),
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$count',
                                  style: AppTextStyles.eyebrow
                                      .copyWith(
                                    color: active
                                        ? Colors.white
                                        : _tabBadgeColor(t.$1),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Divider(color: AppColors.hairline, height: 1),
            ],
          ),
        ),
        // Alert list
        Expanded(
          child: _filtered.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_outlined,
                        size: 36,
                        color: AppColors.slate500.withOpacity(0.3)),
                    const SizedBox(height: 12),
                    Text('No ${_tabs.firstWhere((t) => t.$1 == _tab).$2} alerts',
                        style: AppTextStyles.cardTitle.copyWith(
                            color: AppColors.slate500
                                .withOpacity(0.5))),
                    Text('All clear in this category',
                        style: AppTextStyles.bodySmall),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length + 1,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    if (i == _filtered.length) {
                      return Padding(
                        padding:
                            const EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          '${_tabCount(AlertSeverity.critical)} critical · ${_tabCount(AlertSeverity.high)} high · updated 09:41',
                          style: AppTextStyles.caption,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return _AlertCard(
                      alert: _filtered[i],
                      ackState: _getAck(_filtered[i].id),
                      onAcknowledge: () =>
                          _acknowledge(_filtered[i].id),
                      onViewIncident:
                          _filtered[i].severity ==
                                  AlertSeverity.critical
                              ? widget.onCriticalTap
                              : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AppAlert alert;
  final String ackState;
  final VoidCallback onAcknowledge;
  final VoidCallback? onViewIncident;

  const _AlertCard({
    required this.alert,
    required this.ackState,
    required this.onAcknowledge,
    this.onViewIncident,
  });

  Color get _borderColor {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.signalRed700.withOpacity(0.4);
      case AlertSeverity.high:     return AppColors.saffron600.withOpacity(0.4);
      case AlertSeverity.moderate: return AppColors.navy900.withOpacity(0.2);
      case AlertSeverity.info:     return AppColors.hairline;
    }
  }

  Color get _bgColor {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.signalRed700.withOpacity(0.05);
      case AlertSeverity.high:     return AppColors.saffron600.withOpacity(0.05);
      case AlertSeverity.moderate: return AppColors.navy900.withOpacity(0.03);
      case AlertSeverity.info:     return const Color(0xFFF0F1EC);
    }
  }

  Color get _iconColor {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.signalRed700;
      case AlertSeverity.high:     return AppColors.saffron600;
      case AlertSeverity.moderate: return AppColors.navy900;
      case AlertSeverity.info:     return AppColors.slate500;
    }
  }

  String get _severityLabel {
    switch (alert.severity) {
      case AlertSeverity.critical: return 'CRITICAL';
      case AlertSeverity.high:     return 'HIGH';
      case AlertSeverity.moderate: return 'MODERATE';
      case AlertSeverity.info:     return 'INFO';
    }
  }

  Color get _badgeBg {
    switch (alert.severity) {
      case AlertSeverity.critical: return AppColors.signalRed700;
      case AlertSeverity.high:     return AppColors.saffron600;
      case AlertSeverity.moderate: return AppColors.navy900.withOpacity(0.1);
      case AlertSeverity.info:     return AppColors.slate500.withOpacity(0.1);
    }
  }

  Color get _badgeFg {
    switch (alert.severity) {
      case AlertSeverity.critical: return Colors.white;
      case AlertSeverity.high:     return Colors.white;
      case AlertSeverity.moderate: return AppColors.navy900;
      case AlertSeverity.info:     return AppColors.slate500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_outlined,
                    size: 18, color: _iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _badgeBg,
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                            child: Text(_severityLabel,
                                style: AppTextStyles.eyebrow
                                    .copyWith(
                                  color: _badgeFg,
                                  fontSize: 10,
                                )),
                          ),
                          const Spacer(),
                          Text(alert.time,
                              style: AppTextStyles.caption),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(alert.title,
                          style: AppTextStyles.cardTitle
                              .copyWith(
                                  fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.description,
                    style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Text('📍 ${alert.distance}',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          // Recommended action
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RECOMMENDED ACTION',
                    style: AppTextStyles.eyebrow.copyWith(
                        color: AppColors.slate500.withOpacity(0.5))),
                const SizedBox(height: 4),
                Text(alert.recommendedAction,
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.navy900)),
              ],
            ),
          ),
          // Action buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(
              children: [
                if (alert.incidentId != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onViewIncident,
                      icon: const Icon(Icons.arrow_forward, size: 13),
                      label: const Text('View incident'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8),
                        textStyle: AppTextStyles.buttonSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _AckButton(
                      state: ackState, onTap: onAcknowledge),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AckButton extends StatelessWidget {
  final String state;
  final VoidCallback onTap;
  const _AckButton({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (state == 'done') {
      return Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.deepGreen700.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppColors.deepGreen700.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check, size: 14, color: AppColors.deepGreen700),
            const SizedBox(width: 4),
            Text('Acknowledged',
                style: AppTextStyles.buttonSmall.copyWith(
                    color: AppColors.deepGreen700)),
          ],
        ),
      );
    }
    if (state == 'loading') {
      return Container(
        padding:
            const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.slate500.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.slate500),
            ),
            const SizedBox(width: 6),
            Text('Acknowledging…',
                style: AppTextStyles.buttonSmall.copyWith(
                    color: AppColors.slate500)),
          ],
        ),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        textStyle: AppTextStyles.buttonSmall,
      ),
      child: const Text('Acknowledge'),
    );
  }
}
