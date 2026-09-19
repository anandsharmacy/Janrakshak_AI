import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/rider_location_point.dart';

/// Durable, bounded FIFO of fixes that have not reached Supabase yet.
///
/// Backed by SharedPreferences (one JSON string) which is plenty for the
/// few hundred points a rider accumulates during a coverage gap. When the
/// cap is hit the *oldest* points are dropped — the latest position is what
/// officers care about, and the retained trail stays contiguous at the end.
class LocationQueue {
  LocationQueue(this._prefs, {this.maxItems = 1000, String? key})
      : _key = key ?? _defaultKey;

  static const _defaultKey = 'rider_location_queue_v1';
  static const _lastSyncKey = 'rider_location_last_sync_v1';

  final SharedPreferences _prefs;
  final int maxItems;
  final String _key;

  List<RiderLocationPoint>? _cache;

  List<RiderLocationPoint> get items {
    _cache ??= _read();
    return List.unmodifiable(_cache!);
  }

  int get length => items.length;
  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  DateTime? get lastSyncAt {
    final raw = _prefs.getString(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> markSynced([DateTime? at]) =>
      _prefs.setString(_lastSyncKey, (at ?? DateTime.now()).toUtc().toIso8601String());

  Future<void> enqueue(RiderLocationPoint point) async {
    final list = [..._cache ?? _read()];
    // Replace an existing entry with the same client id (re-queued retry).
    list.removeWhere((p) => p.clientId == point.clientId);
    list.add(point);
    if (list.length > maxItems) {
      list.removeRange(0, list.length - maxItems);
    }
    await _write(list);
  }

  /// Oldest-first batch for upload.
  List<RiderLocationPoint> take(int n) {
    final all = items;
    return all.length <= n ? all : all.sublist(0, n);
  }

  Future<void> removeByIds(Iterable<String> clientIds) async {
    final ids = clientIds.toSet();
    final list = (_cache ?? _read()).where((p) => !ids.contains(p.clientId)).toList();
    await _write(list);
  }

  Future<void> clear() => _write(const []);

  List<RiderLocationPoint> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => RiderLocationPoint.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      // Corrupt payload: drop it rather than wedge the uploader forever.
      return [];
    }
  }

  Future<void> _write(List<RiderLocationPoint> list) async {
    _cache = list;
    if (list.isEmpty) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, jsonEncode(list.map((p) => p.toJson()).toList()));
    }
  }
}
