import 'package:flutter_test/flutter_test.dart';
import 'package:ner_logistics/features/rider/application/location_queue.dart';
import 'package:ner_logistics/features/rider/domain/rider_location_point.dart';
import 'package:shared_preferences/shared_preferences.dart';

RiderLocationPoint _pt(String id, int seconds) => RiderLocationPoint(
      clientId: id,
      lat: 25.9,
      lng: 91.8,
      recordedAt: DateTime.utc(2026, 9, 12, 10).add(Duration(seconds: seconds)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enqueue persists and survives a new queue instance', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final q = LocationQueue(prefs);
    await q.enqueue(_pt('a', 0));
    await q.enqueue(_pt('b', 10));
    expect(q.length, 2);

    final reloaded = LocationQueue(prefs);
    expect(reloaded.items.map((p) => p.clientId), ['a', 'b']);
  });

  test('take returns oldest first and removeByIds drops uploaded points', () async {
    SharedPreferences.setMockInitialValues({});
    final q = LocationQueue(await SharedPreferences.getInstance());
    for (var i = 0; i < 5; i++) {
      await q.enqueue(_pt('p$i', i * 10));
    }
    final batch = q.take(3);
    expect(batch.map((p) => p.clientId), ['p0', 'p1', 'p2']);
    await q.removeByIds(batch.map((p) => p.clientId));
    expect(q.items.map((p) => p.clientId), ['p3', 'p4']);
  });

  test('re-enqueue with the same client id replaces instead of duplicating', () async {
    SharedPreferences.setMockInitialValues({});
    final q = LocationQueue(await SharedPreferences.getInstance());
    await q.enqueue(_pt('same', 0));
    await q.enqueue(_pt('same', 5));
    expect(q.length, 1);
    expect(q.items.single.recordedAt.second, 5);
  });

  test('cap drops the oldest points', () async {
    SharedPreferences.setMockInitialValues({});
    final q = LocationQueue(await SharedPreferences.getInstance(), maxItems: 3);
    for (var i = 0; i < 5; i++) {
      await q.enqueue(_pt('p$i', i));
    }
    expect(q.items.map((p) => p.clientId), ['p2', 'p3', 'p4']);
  });

  test('corrupt payload is discarded instead of throwing', () async {
    SharedPreferences.setMockInitialValues({'rider_location_queue_v1': '{not json'});
    final q = LocationQueue(await SharedPreferences.getInstance());
    expect(q.items, isEmpty);
    await q.enqueue(_pt('ok', 0));
    expect(q.length, 1);
  });

  test('markSynced records the last sync time', () async {
    SharedPreferences.setMockInitialValues({});
    final q = LocationQueue(await SharedPreferences.getInstance());
    expect(q.lastSyncAt, isNull);
    final at = DateTime.utc(2026, 9, 12, 11);
    await q.markSynced(at);
    expect(q.lastSyncAt, at);
  });
}
