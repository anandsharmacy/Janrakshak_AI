import '../core/demo/demo_mode.dart';
import 'models.dart';

/// The sample tasks while demo mode is on, otherwise none.
List<FieldTask> buildMockTasks() => DemoMode.enabled ? _buildDemoTasks() : <FieldTask>[];

List<FieldTask> _buildDemoTasks() => [
      FieldTask(
        id: 'TSK-001',
        title: 'Inspect NH-6 Km 22–26 slope damage',
        location: 'NH-6, Km 22–26',
        priority: Priority.critical,
        dueTime: '10:30',
        createdTime: '07:00',
        status: TaskStatus.inProgress,
        acceptedAt: '07:45',
      ),
      FieldTask(
        id: 'TSK-002',
        title: 'Coordinate medical convoy LOG-4471',
        location: 'NH-6, Km 18',
        priority: Priority.high,
        dueTime: '11:00',
        createdTime: '08:00',
        status: TaskStatus.pending,
      ),
      FieldTask(
        id: 'TSK-003',
        title: 'Report bridge condition — Lubha',
        location: 'Lubha bridge, Km 26',
        priority: Priority.high,
        dueTime: '12:00',
        createdTime: '06:00',
        status: TaskStatus.pending,
      ),
      FieldTask(
        id: 'TSK-004',
        title: 'Daily area situation report',
        location: 'Ri Bhoi district HQ',
        priority: Priority.medium,
        dueTime: '17:00',
        createdTime: '07:00',
        status: TaskStatus.completed,
        acceptedAt: '07:30',
      ),
      FieldTask(
        id: 'TSK-005',
        title: 'Verify road clearing at Km 31',
        location: 'SH-5, Km 31',
        priority: Priority.critical,
        dueTime: '09:00',
        createdTime: '06:30',
        status: TaskStatus.overdue,
      ),
      FieldTask(
        id: 'TSK-006',
        title: 'Check Umiam checkpoint logbook',
        location: 'Umiam checkpoint',
        priority: Priority.medium,
        dueTime: '14:00',
        createdTime: '08:30',
        status: TaskStatus.pending,
      ),
      FieldTask(
        id: 'TSK-007',
        title: 'Submit logistics delay report',
        location: 'Field / mobile',
        priority: Priority.high,
        dueTime: '13:00',
        createdTime: '09:00',
        status: TaskStatus.inProgress,
        acceptedAt: '09:10',
      ),
      FieldTask(
        id: 'TSK-008',
        title: 'Community liaison — Jorabat',
        location: 'Jorabat village',
        priority: Priority.low,
        dueTime: '16:00',
        createdTime: '08:00',
        status: TaskStatus.completed,
        acceptedAt: '08:15',
      ),
    ];
