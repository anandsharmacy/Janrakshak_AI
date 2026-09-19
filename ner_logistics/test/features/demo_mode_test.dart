import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/core/demo/demo_mode.dart';
import 'package:ner_logistics/features/field_officer/dashboard/field_dashboard.dart';
import 'package:ner_logistics/features/rider/application/rider_tracking_controller.dart';
import 'package:ner_logistics/features/rider/rider_dashboard.dart';
import 'package:ner_logistics/features/rider/rider_drawer.dart';
import 'package:ner_logistics/mock_data/mock_alerts.dart';
import 'package:ner_logistics/mock_data/mock_deliveries.dart';
import 'package:ner_logistics/mock_data/mock_fleet.dart';
import 'package:ner_logistics/mock_data/mock_incidents.dart' hide mockDistricts, mockFleet;
import 'package:ner_logistics/mock_data/mock_repository.dart';
import 'package:ner_logistics/mock_data/mock_routes.dart';
import 'package:ner_logistics/mock_data/mock_shipments.dart';
import 'package:ner_logistics/mock_data/mock_tasks.dart';
import 'package:ner_logistics/services/routing/trip_plan.dart';
import 'package:ner_logistics/shared/widgets/demo_toggle.dart';

void main() {
  setUp(() => DemoMode.enabled = true);
  tearDown(() => DemoMode.enabled = true);

  test('sample data is populated while demo mode is on', () {
    expect(mockAlerts, isNotEmpty);
    expect(mockIncidents, isNotEmpty);
    expect(mockFleet, isNotEmpty);
    expect(mockRoutes, isNotEmpty);
    expect(mockShipments, isNotEmpty);
    expect(mockRiderDeliveries, isNotEmpty);
    expect(buildMockTasks(), isNotEmpty);
    expect(TripSnapshots.riderPlan(), isNotNull);
    expect(MockAppState.initial().activeRiderAssignment, isNotNull);
  });

  test('sample data is empty while demo mode is off', () {
    DemoMode.enabled = false;
    expect(mockAlerts, isEmpty);
    expect(mockIncidents, isEmpty);
    expect(mockFleet, isEmpty);
    expect(mockRoutes, isEmpty);
    expect(mockNearbyIncidents, isEmpty);
    expect(mockShipments, isEmpty);
    expect(mockRiderDeliveries, isEmpty);
    expect(buildMockTasks(), isEmpty);
    expect(TripSnapshots.riderPlan(), isNull);
    expect(TripSnapshots.fieldPlan(), isNull);
    expect(TripSnapshots.fieldDetour(), isNull);
    expect(MockAppState.initial().activeRiderAssignment, isNull);
    expect(demoOnly([1, 2]), isEmpty);
  });

  testWidgets('header toggle flips demo mode', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: DemoToggle())),
    ));
    expect(find.text('DEMO ON'), findsOneWidget);

    await tester.tap(find.byType(DemoToggle));
    await tester.pump();
    expect(find.text('DEMO OFF'), findsOneWidget);
    expect(DemoMode.enabled, isFalse);

    await tester.tap(find.byType(DemoToggle));
    await tester.pump();
    expect(find.text('DEMO ON'), findsOneWidget);
    expect(DemoMode.enabled, isTrue);
  });

  testWidgets('rider screens render without any assignment', (tester) async {
    DemoMode.enabled = false;
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final section in [RiderNav.dashboard, RiderNav.deliveries, RiderNav.trip]) {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RiderDashboard(
              section: section,
              appState: MockAppState.initial(),
              onNavigate: (_) {},
              onToggleOffline: () {},
              onStartTrip: () {},
              onPauseTrip: () {},
              onResumeTrip: () {},
              onAccept: () {},
              onComplete: () {},
              onAddProof: () {},
              onReportIssue: () {},
              onDownloadMap: (_) {},
              onRefreshMap: (_) {},
              tracking: const RiderTrackingState(),
              riderContext: null,
              online: true,
              onToggleSharing: () {},
              onCheckIn: () {},
              onRetrySync: () {},
              onDismissTrackingError: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$section');
    }
  });

  testWidgets('field dashboard renders with demo mode off', (tester) async {
    DemoMode.enabled = false;
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FieldDashboard(
          isOffline: false,
          onToggleOffline: () {},
          onStartTask: () {},
          onOpenTasks: () {},
          onViewIncidents: () {},
          onReportType: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Nearby Incidents'), findsNothing);
    expect(find.text('Quick Actions'), findsOneWidget);
  });
}
