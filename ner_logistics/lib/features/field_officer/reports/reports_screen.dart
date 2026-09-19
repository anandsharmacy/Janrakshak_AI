import 'package:flutter/material.dart';
import 'package:ner_logistics/theme/colors.dart';
import 'package:ner_logistics/theme/text_styles.dart';

enum ReportActions { view, download, generate }

enum ActionState { idle, loading, done }

String _viewLabel(ActionState state) {
  switch (state) {
    case ActionState.idle:
      return 'View';
    case ActionState.loading:
      return 'Loading…';
    case ActionState.done:
      return 'Done';
  }
}

String _secondaryLabel(ReportActions action, ActionState state) {
  switch (state) {
    case ActionState.idle:
      return action == ReportActions.download ? 'Download' : 'Generate';
    case ActionState.loading:
      return action == ReportActions.download ? 'Downloading…' : 'Generating…';
    case ActionState.done:
      return 'Done';
  }
}

class _SectionData {
  final String title;
  final String subtitle;
  final IconData icon;
  final ReportActions secondaryAction;
  final String secondaryLabel;

  const _SectionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.secondaryAction,
    required this.secondaryLabel,
  });
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final Map<int, Map<ReportActions, ActionState>> _states;

  static const List<_SectionData> _sections = [
    _SectionData(
      title: 'Incident Reports',
      subtitle: '12 total · 3 pending sync',
      icon: Icons.description_outlined,
      secondaryAction: ReportActions.download,
      secondaryLabel: 'Download',
    ),
    _SectionData(
      title: 'Completed Tasks',
      subtitle: '8 completed · 2 this week',
      icon: Icons.check_circle_outline,
      secondaryAction: ReportActions.generate,
      secondaryLabel: 'Generate',
    ),
    _SectionData(
      title: 'Route Inspections',
      subtitle: '5 inspections · last: yesterday',
      icon: Icons.route_outlined,
      secondaryAction: ReportActions.generate,
      secondaryLabel: 'Generate',
    ),
    _SectionData(
      title: 'Logistics Observations',
      subtitle: '4 reports · all synced',
      icon: Icons.local_shipping_outlined,
      secondaryAction: ReportActions.download,
      secondaryLabel: 'Download',
    ),
    _SectionData(
      title: 'Daily Activity Reports',
      subtitle: '7 days · today pending',
      icon: Icons.note_alt_outlined,
      secondaryAction: ReportActions.generate,
      secondaryLabel: 'Generate',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _states = {
      for (int i = 0; i < _sections.length; i++)
        i: {
          ReportActions.view: ActionState.idle,
          _sections[i].secondaryAction: ActionState.idle,
        },
    };
  }

  Future<void> _handleAction(int sectionIndex, ReportActions action) async {
    setState(() {
      _states[sectionIndex]![action] = ActionState.loading;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _states[sectionIndex]![action] = ActionState.done;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _states[sectionIndex]![action] = ActionState.idle;
    });
  }

  String _viewLabel(ActionState state) {
    switch (state) {
      case ActionState.idle:
        return 'View';
      case ActionState.loading:
        return 'Loading…';
      case ActionState.done:
        return 'Done';
    }
  }

  String _secondaryLabel(ReportActions action, ActionState state) {
    switch (state) {
      case ActionState.idle:
        return action == ReportActions.download ? 'Download' : 'Generate';
      case ActionState.loading:
        return action == ReportActions.download ? 'Downloading…' : 'Generating…';
      case ActionState.done:
        return 'Done';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports',
                style: AppTextStyles.pageHeading,
              ),
              const SizedBox(height: 4),
              Text(
                'Field reports · Ri Bhoi district',
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Column(
                children: [
                  for (int i = 0; i < _sections.length; i++) ...[
                    _SectionCard(
                      data: _sections[i],
                      viewState: _states[i]![ReportActions.view]!,
                      secondaryState: _states[i]![_sections[i].secondaryAction]!,
                      onView: () => _handleAction(i, ReportActions.view),
                      onSecondary: () => _handleAction(i, _sections[i].secondaryAction),
                    ),
                    if (i < _sections.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Reports auto-generate daily at 23:59. Offline reports sync when connection is restored.',
                style: TextStyle(
                  fontFamily: 'NotoSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.ink.withValues(alpha: 0.5),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _SectionData data;
  final ActionState viewState;
  final ActionState secondaryState;
  final VoidCallback onView;
  final VoidCallback onSecondary;

  const _SectionCard({
    required this.data,
    required this.viewState,
    required this.secondaryState,
    required this.onView,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.navy900.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              data.icon,
              color: AppColors.navy900,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: AppTextStyles.cardTitle,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.subtitle,
                            style: TextStyle(
                              fontFamily: 'NotoSans',
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AppColors.ink,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionButton(
                          label: _viewLabel(viewState),
                          isPrimary: true,
                          state: viewState,
                          onTap: onView,
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          label: _secondaryLabel(data.secondaryAction, secondaryState),
                          isPrimary: false,
                          state: secondaryState,
                          onTap: onSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final ActionState state;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.isPrimary,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = state == ActionState.loading || state == ActionState.done;

    final Color borderColor;
    final Color textColor;
    if (isPrimary) {
      borderColor = AppColors.navy900;
      textColor = AppColors.navy900;
    } else {
      borderColor = AppColors.ink.withValues(alpha: 0.30);
      textColor = AppColors.ink;
    }

    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: 1),
          color: state == ActionState.done
              ? (isPrimary
                  ? AppColors.navy900.withValues(alpha: 0.08)
                  : AppColors.ink.withValues(alpha: 0.08))
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == ActionState.loading) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'PublicSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: state == ActionState.done
                    ? (isPrimary
                        ? AppColors.navy900
                        : AppColors.ink)
                    : textColor,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
