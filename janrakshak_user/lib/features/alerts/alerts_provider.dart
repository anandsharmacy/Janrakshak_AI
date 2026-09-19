import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../data/feed.dart';
import '../../data/hazard.dart';
import '../../data/providers.dart';
import '../../data/store.dart';
import '../../data/taxonomy.dart';
import '../trip_planner/trip_store.dart';

enum AlertFilter {
  region('My Region'),
  trip('Active Trip Route'),
  all('All');

  const AlertFilter(this.label);
  final String label;
}

class AlertFilterNotifier extends Notifier<AlertFilter> {
  @override
  AlertFilter build() => AlertFilter.region;
  void set(AlertFilter f) => state = f;
}

final alertFilterProvider = NotifierProvider<AlertFilterNotifier, AlertFilter>(AlertFilterNotifier.new);

/// Prioritised feed: most severe first, then newest.
final _sortedProvider = Provider<List<Hazard>>((ref) => [...ref.watch(hazardsProvider)]
  ..sort((a, b) {
    final s = b.severity.index.compareTo(a.severity.index);
    return s != 0 ? s : b.at.compareTo(a.at);
  }));

bool _onRoute(Hazard h, ActiveRoute? r) => r != null && r.points.any(h.covers);

/// Alerts for the user's region (null region = location unknown, so nothing is filtered out).
final regionAlertsProvider = Provider<List<Hazard>>((ref) {
  final region = ref.watch(myPlaceProvider).value?.region;
  final all = ref.watch(_sortedProvider);
  return region == null ? all : all.where((h) => h.region == region).toList();
});

final filteredAlertsProvider = Provider<List<Hazard>>((ref) {
  final all = ref.watch(_sortedProvider);
  return switch (ref.watch(alertFilterProvider)) {
    AlertFilter.all => all,
    AlertFilter.region => ref.watch(regionAlertsProvider),
    AlertFilter.trip => () {
        final r = ref.watch(activeRouteProvider);
        return all.where((h) => _onRoute(h, r)).toList();
      }(),
  };
});

// ---- Local notifications -------------------------------------------------------------------

final notifications = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  await notifications.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

const _notifyAt = {Severity.high, Severity.critical};

Future<void> _notify(Hazard h, String why) async {
  final key = 'notified_${h.id}';
  if (Store.settings.get(key) != null) return; // once per hazard
  await Store.settings.put(key, why);
  await notifications.show(
    id: h.id.hashCode & 0x7fffffff,
    title: '${h.severity.label}: ${h.type} - ${h.district}',
    body: '$why. ${h.summary}',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails('priority_alerts', 'Priority alerts',
          channelDescription: 'High and critical hazards near you or on your active trip',
          importance: Importance.max,
          priority: Priority.high),
    ),
  );
}

/// Fires a notification when live GPS or the active trip route enters a High/Critical hazard zone.
/// Runs only while the app process is alive.
// ponytail: no background location service; add a foreground service or a WorkManager periodic check for closed-app alerts.
final alertWatcherProvider = Provider<void>((ref) {
  final route = ref.watch(activeRouteProvider);
  final hazards = ref.watch(hazardsProvider);
  var disposed = false;
  StreamSubscription<Position>? sub;

  void check(LatLng? here) {
    for (final h in hazards.where((h) => _notifyAt.contains(h.severity))) {
      if (here != null && h.covers(here)) {
        _notify(h, 'You are inside the affected area');
      } else if (_onRoute(h, route)) {
        _notify(h, 'Your active trip route passes through it');
      }
    }
  }

  check(null);
  () async {
    final p = await currentPosition();
    if (p == null || disposed) return;
    check(LatLng(p.latitude, p.longitude));
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 500),
    ).listen((p) => check(LatLng(p.latitude, p.longitude)), onError: (Object e) => debugPrint('position stream: $e'));
  }();
  ref.onDispose(() {
    disposed = true;
    sub?.cancel();
  });
});
