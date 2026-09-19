import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:janrakshak_user/data/feed.dart';
import 'package:janrakshak_user/data/auth.dart';
import 'package:janrakshak_user/data/providers.dart';
import 'package:janrakshak_user/data/region_data.dart';
import 'package:janrakshak_user/main.dart';
import 'package:janrakshak_user/router.dart';
import 'package:latlong2/latlong.dart';

import 'logic_test.dart' show openTestStore, sampleHazards;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every tab and the trip planner render at 360x800 without errors', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await RegionData.load();
      await openTestStore();
    });

    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sessionProvider.overrideWith((_) => Stream.value(null)),
        hazardFeedProvider.overrideWith((_) async => Feed(sampleHazards)),
        onlineProvider.overrideWith((_) => Stream.value(true)),
        positionProvider.overrideWith((_) async => null),
        myPlaceProvider.overrideWith((_) async =>
            const Place(pos: LatLng(24.83, 92.78), state: 'Assam', district: 'Cachar')),
      ],
      child: JanRakshakApp(createRouter(refresh: ValueNotifier(0), signedIn: () => true)),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Northeast'), findsOneWidget); // Active region header on Home
    expect(find.text('Floods'), findsWidgets); // live feed alert rendered on Home

    for (final tab in ['Map', 'Report', 'Alerts', 'Contacts', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(GoogleFonts.pendingFonts); // asset fonts load async; settle before asserting
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'tab $tab');
    }

    await tester.tap(find.text('Trip planner'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Check route & navigate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out users are redirected to the sign-in screen', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(RegionData.load);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [sessionProvider.overrideWith((_) => Stream.value(null))],
      child: JanRakshakApp(createRouter(refresh: ValueNotifier(0), signedIn: () => false)),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Sign in'), findsWidgets);
    await tester.tap(find.text('New here? Create an account'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Create your account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
