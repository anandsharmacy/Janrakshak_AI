import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/features/auth/application/auth_controller.dart';
import 'package:ner_logistics/features/auth/domain/auth_models.dart';
import 'package:ner_logistics/features/rider/logistics/application/rider_logistics_service.dart';
import 'package:ner_logistics/features/rider/logistics/presentation/rider_logistics_panel.dart';
import 'package:ner_logistics/mock_data/models.dart';

const _lyngdoh = AuthUserProfile(
  userId: '00000000-0000-0000-0000-000000000004',
  email: 'p.lyngdoh@ner.gov.in',
  fullName: 'P. Lyngdoh',
  officerId: 'NER-RD-1184',
  role: AppRole.rider,
);

Future<void> _phone(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('panel renders the signed-in rider, route card and diversion flow', (t) async {
    await _phone(t);
    final container = ProviderContainer(overrides: [
      currentProfileProvider.overrideWithValue(_lyngdoh),
      riderLogisticsAutoTickProvider.overrideWithValue(false),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RiderLogisticsPanel(isOffline: true))),
      ),
    ));
    await t.pump(const Duration(milliseconds: 50));

    // Identity from the session → dataset mapping, never a rider picker.
    expect(find.text('Rohan Das'), findsOneWidget);
    expect(find.textContaining('FALCON-1 · R001'), findsOneWidget);
    expect(find.text('CURRENT ROUTE'), findsOneWidget);
    expect(find.text('Shillong Depot'), findsWidgets);
    expect(find.text('NER-12'), findsOneWidget);
    expect(find.text('OPEN'), findsWidgets);
    expect(find.text('DEMO DATA'), findsOneWidget);
    // Nearby rider shown without a phone number.
    expect(find.textContaining('Banlum Khonglah'), findsWidgets);
    expect(find.textContaining('9876543215'), findsNothing);
    expect(find.textContaining('Kevichusa'), findsNothing);
    expect(find.text('Confirm diversion'), findsNothing);

    // Drive to the incident; the warning and the confirm action appear.
    final service = container.read(riderLogisticsProvider.notifier);
    while (!container.read(riderLogisticsProvider).canConfirmDiversion) {
      service.tick();
    }
    await t.pump();
    expect(find.text('Route safety warning'), findsOneWidget);
    expect(find.textContaining('Incident reported ahead on your route near Umiam'), findsOneWidget);
    expect(find.text('AT RISK'), findsWidgets);
    expect(find.text('Confirm diversion'), findsOneWidget);

    await t.tap(find.text('Confirm diversion'));
    await t.pump();
    expect(find.text('DIVERTED'), findsWidgets);
    expect(find.text('Following the alternate route'), findsOneWidget);
    expect(find.text('Confirm diversion'), findsNothing);

    await t.pumpWidget(const SizedBox());
  });
}
