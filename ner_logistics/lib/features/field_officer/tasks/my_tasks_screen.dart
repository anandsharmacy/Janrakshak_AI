import 'package:flutter/material.dart';
import '../../../mock_data/mock_tasks.dart';
import '../../../mock_data/models.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

class MyTasksScreen extends StatefulWidget {
  final VoidCallback onBack;
  const MyTasksScreen({super.key, required this.onBack});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  late List<FieldTask> _tasks;
  TaskStatus? _filter; // null = all

  static const _tabs = [
    (null,              'All'),
    (TaskStatus.pending,    'Pending'),
    (TaskStatus.inProgress, 'In Progress'),
    (TaskStatus.awaitingVerification, 'Awaiting Verification'),
    (TaskStatus.completed,  'Completed'),
    (TaskStatus.overdue,    'Overdue'),
  ];

  @override
  void initState() {
    super.initState();
    _tasks = buildMockTasks();
  }

  List<FieldTask> get _filtered => _filter == null
      ? _tasks
      : _tasks.where((t) => t.status == _filter).toList();

  int _count(TaskStatus? s) =>
      s == null ? _tasks.length : _tasks.where((t) => t.status == s).length;

  void _accept(String id) => setState(() {
        _tasks = _tasks.map((t) {
          if (t.id == id) {
            t.status = TaskStatus.inProgress;
            t.acceptedAt = 'now';
          }
          return t;
        }).toList();
      });

  void _complete(String id) => setState(() {
        _tasks = _tasks.map((t) {
          if (t.id == id) t.status = TaskStatus.awaitingVerification;
          return t;
        }).toList();
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back + heading
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_ios, size: 16),
                label: const Text('Home'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.navy900,
                ),
              ),
              const SizedBox(height: 8),
              Text('My Tasks', style: AppTextStyles.pageHeading),
              Text('Ri Bhoi district · today',
                  style: AppTextStyles.bodySmall),
            ],
          ),
        ),
        // Tab bar
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _tabs.map((tab) {
              final active = _filter == tab.$1;
              return GestureDetector(
                onTap: () => setState(() => _filter = tab.$1),
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
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
                        tab.$2,
                        style: AppTextStyles.tabLabel.copyWith(
                          color: active
                              ? AppColors.navy900
                              : AppColors.slate500,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.navy900
                              : AppColors.slate500
                                  .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_count(tab.$1)}',
                          style: AppTextStyles.eyebrow.copyWith(
                            color: active
                                ? Colors.white
                                : AppColors.slate500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Divider(color: AppColors.hairline, height: 1),
        // Task list
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text('No tasks in this category.',
                      style: AppTextStyles.bodySmall),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 12),
                  itemBuilder: (_, i) => _TaskCard(
                    task: _filtered[i],
                    onAccept: _accept,
                    onComplete: _complete,
                  ),
                ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final FieldTask task;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onComplete;

  const _TaskCard({
    required this.task,
    required this.onAccept,
    required this.onComplete,
  });

  ChipTone get _statusTone {
    switch (task.status) {
      case TaskStatus.pending:    return ChipTone.saffron;
      case TaskStatus.inProgress: return ChipTone.navy;
      case TaskStatus.awaitingVerification: return ChipTone.saffron;
      case TaskStatus.completed:  return ChipTone.clear;
      case TaskStatus.overdue:    return ChipTone.critical;
    }
  }

  String get _statusLabel {
    switch (task.status) {
      case TaskStatus.pending:    return 'Pending';
      case TaskStatus.inProgress: return 'In Progress';
      case TaskStatus.awaitingVerification: return 'Awaiting Verification';
      case TaskStatus.completed:  return 'Completed';
      case TaskStatus.overdue:    return 'Overdue';
    }
  }

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(task.id, style: AppTextStyles.caption),
              const SizedBox(width: 8),
              PriorityBadge(level: task.priority),
              const Spacer(),
              StatusChip(
                  tone: _statusTone, label: _statusLabel),
            ],
          ),
          const SizedBox(height: 8),
          Text(task.title,
              style: AppTextStyles.cardTitle.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 14,
                  color: AppColors.slate500.withOpacity(0.7)),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(task.location,
                      style: AppTextStyles.bodySmall)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time_outlined,
                  size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Text('Due ${task.dueTime}',
                  style: AppTextStyles.caption),
              const SizedBox(width: 12),
              Text('Created ${task.createdTime}',
                  style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 12),
          _ActionRow(
              task: task,
              onAccept: onAccept,
              onComplete: onComplete),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final FieldTask task;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onComplete;
  const _ActionRow(
      {required this.task,
      required this.onAccept,
      required this.onComplete});

  @override
  Widget build(BuildContext context) {
    switch (task.status) {
      case TaskStatus.pending:
        return OutlinedButton(
          onPressed: () => onAccept(task.id),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
            textStyle: AppTextStyles.buttonSmall,
          ),
          child: const Text('Accept'),
        );
      case TaskStatus.inProgress:
        return ElevatedButton(
          onPressed: () => onComplete(task.id),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
            textStyle: AppTextStyles.buttonSmall,
          ),
          child: const Text('Mark Complete'),
        );
      case TaskStatus.awaitingVerification:
        return Text('Submitted for verification',
            style: AppTextStyles.captionSemibold.copyWith(
                color: AppColors.saffronDark));
      case TaskStatus.completed:
        return Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 14, color: AppColors.deepGreen700),
            const SizedBox(width: 4),
            Text('Verified',
                style: AppTextStyles.captionSemibold.copyWith(
                    color: AppColors.deepGreen700)),
          ],
        );
      case TaskStatus.overdue:
        return ElevatedButton(
          onPressed: () => onAccept(task.id),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.signalRed700,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
            textStyle: AppTextStyles.buttonSmall,
          ),
          child: const Text('Accept & Start'),
        );
    }
  }
}
