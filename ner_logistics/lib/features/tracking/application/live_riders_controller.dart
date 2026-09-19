import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/connectivity_provider.dart';
import '../data/live_rider_repository.dart';
import '../domain/live_rider.dart';

/// How the officer screen is currently receiving updates.
enum LiveFeedStatus { connecting, live, polling, error }

class LiveRidersState {
  final Map<String, LiveRider> riders;
  final LiveFeedStatus feed;
  final DateTime now;
  final DateTime? lastRefresh;
  final String? error;
  final String? selectedId;
  final List<LatLng> trail;
  final bool trailLoading;
  final Duration staleWindow;

  const LiveRidersState({
    required this.riders,
    required this.feed,
    required this.now,
    this.lastRefresh,
    this.error,
    this.selectedId,
    this.trail = const [],
    this.trailLoading = false,
    this.staleWindow = const Duration(minutes: 30),
  });

  /// Active riders first (fresh + on duty), then by most recent fix.
  List<LiveRider> get sorted {
    final list = riders.values.toList();
    int rank(LiveRider r) => r.isActiveAt(now, window: staleWindow) ? 0 : r.isStaleAt(now, window: staleWindow) ? 2 : 1;
    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : b.recordedAt.compareTo(a.recordedAt);
    });
    return list;
  }

  LiveRider? get selected => selectedId == null ? null : riders[selectedId];

  int get total => riders.length;
  int get activeCount => riders.values.where((r) => r.isActiveAt(now, window: staleWindow)).length;
  int get movingCount => riders.values.where((r) => r.isMoving && !r.isStaleAt(now, window: staleWindow)).length;
  int get staleCount => riders.values.where((r) => r.isStaleAt(now, window: staleWindow)).length;

  LiveRidersState copyWith({
    Map<String, LiveRider>? riders,
    LiveFeedStatus? feed,
    DateTime? now,
    DateTime? lastRefresh,
    Object? error = _sentinel,
    Object? selectedId = _sentinel,
    List<LatLng>? trail,
    bool? trailLoading,
  }) =>
      LiveRidersState(
        riders: riders ?? this.riders,
        feed: feed ?? this.feed,
        now: now ?? this.now,
        lastRefresh: lastRefresh ?? this.lastRefresh,
        error: identical(error, _sentinel) ? this.error : error as String?,
        selectedId: identical(selectedId, _sentinel) ? this.selectedId : selectedId as String?,
        trail: trail ?? this.trail,
        trailLoading: trailLoading ?? this.trailLoading,
        staleWindow: staleWindow,
      );

  static const _sentinel = Object();
}

/// Keeps the officer's view of all riders current.
///
/// * Initial load: `get_active_riders` RPC
/// * Live updates: Realtime on `rider_locations` + `rider_profiles`
/// * Fallback: polling every 30 s while the channel is not subscribed, and a
///   safety refresh every 2 min even when live (catches anything missed)
/// * A 20 s tick refreshes "x min ago" labels and staleness without traffic
///
/// Auto-disposed: the channel closes when no screen is watching.
class LiveRidersController extends AutoDisposeAsyncNotifier<LiveRidersState> {
  static const _pollEvery = Duration(seconds: 30);
  static const _safetyRefreshEvery = Duration(minutes: 2);
  static const _tickEvery = Duration(seconds: 20);
  static const _resubscribeAfter = Duration(seconds: 10);

  RealtimeChannel? _channel;
  Timer? _poll;
  Timer? _tick;
  Timer? _resubscribe;
  Timer? _refetchDebounce;
  DateTime _lastFullRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  LiveRiderRepository get _repo => ref.read(liveRiderRepositoryProvider);

  @override
  Future<LiveRidersState> build() async {
    _disposed = false;
    ref.onDispose(_dispose);
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
      if ((next.valueOrNull ?? true) && (prev?.valueOrNull ?? true) == false) {
        unawaited(refresh());
        _openChannel();
      }
    });

    final riders = await _repo.fetchActive();
    _lastFullRefresh = DateTime.now();
    _openChannel();
    _tick = Timer.periodic(_tickEvery, (_) => _onTick());
    _poll = Timer.periodic(_pollEvery, (_) => _onPoll());

    return LiveRidersState(
      riders: {for (final r in riders) r.userId: r},
      feed: LiveFeedStatus.connecting,
      now: DateTime.now(),
      lastRefresh: DateTime.now(),
    );
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> refresh() async {
    final current = state.valueOrNull;
    try {
      final riders = await _repo.fetchActive();
      _lastFullRefresh = DateTime.now();
      if (_disposed) return;
      final map = {for (final r in riders) r.userId: r};
      final keepSelected = current?.selectedId;
      state = AsyncData((current ?? _empty()).copyWith(
        riders: map,
        now: DateTime.now(),
        lastRefresh: DateTime.now(),
        error: null,
        selectedId: keepSelected != null && map.containsKey(keepSelected) ? keepSelected : null,
      ));
    } catch (e) {
      if (_disposed) return;
      if (current == null) {
        state = AsyncError(e, StackTrace.current);
      } else {
        state = AsyncData(current.copyWith(error: _message(e), now: DateTime.now()));
      }
    }
  }

  /// Selects a rider (or clears with null) and loads their recent trail.
  Future<void> select(String? userId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (userId == null || current.selectedId == userId) {
      state = AsyncData(current.copyWith(selectedId: null, trail: const [], trailLoading: false));
      return;
    }
    state = AsyncData(current.copyWith(selectedId: userId, trail: const [], trailLoading: true));
    try {
      final trail = await _repo.fetchTrail(userId);
      final latest = state.valueOrNull;
      if (_disposed || latest == null || latest.selectedId != userId) return;
      state = AsyncData(latest.copyWith(trail: trail.map((t) => t.point).toList(), trailLoading: false));
    } catch (e) {
      final latest = state.valueOrNull;
      if (_disposed || latest == null) return;
      state = AsyncData(latest.copyWith(trailLoading: false, error: 'Trail unavailable: ${_message(e)}'));
    }
  }

  // ── Realtime ──────────────────────────────────────────────────────────────

  void _openChannel() {
    if (_disposed) return;
    final old = _channel;
    if (old != null) unawaited(_repo.unsubscribe(old));
    _channel = _repo.subscribe(
      onLocation: _onLocation,
      onProfile: _onProfile,
      onStatus: _onStatus,
    );
  }

  void _onStatus(RealtimeSubscribeStatus status, Object? error) {
    if (_disposed) return;
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _setFeed(LiveFeedStatus.live);
        // Anything that changed while (re)connecting.
        if (DateTime.now().difference(_lastFullRefresh) > const Duration(seconds: 5)) {
          unawaited(refresh());
        }
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        debugPrint('Realtime rider channel $status: $error');
        _setFeed(LiveFeedStatus.polling);
        _resubscribe?.cancel();
        _resubscribe = Timer(_resubscribeAfter, _openChannel);
      case RealtimeSubscribeStatus.closed:
        _setFeed(LiveFeedStatus.polling);
    }
  }

  void _onLocation(Map<String, dynamic> row) {
    final current = state.valueOrNull;
    final id = row['user_id'] as String?;
    if (current == null || id == null) return;
    var existing = current.riders[id];
    if (existing == null || existing.needsShipmentRefresh(row)) {
      // New rider (or new shipment) — fetch the joined details.
      _scheduleRefetch();
      if (existing == null) return;
    }
    final updated = existing.mergeLocation(row);
    if (identical(updated, existing)) return;
    final riders = Map<String, LiveRider>.from(current.riders)..[id] = updated;
    var next = current.copyWith(riders: riders, now: DateTime.now());
    if (current.selectedId == id && current.trail.isNotEmpty) {
      next = next.copyWith(trail: [...current.trail, updated.point]);
    }
    state = AsyncData(next);
  }

  void _onProfile(Map<String, dynamic> row) {
    final current = state.valueOrNull;
    final id = row['user_id'] as String?;
    if (current == null || id == null) return;
    final existing = current.riders[id];
    if (existing == null) {
      _scheduleRefetch();
      return;
    }
    final riders = Map<String, LiveRider>.from(current.riders)..[id] = existing.mergeProfile(row);
    state = AsyncData(current.copyWith(riders: riders, now: DateTime.now()));
  }

  void _scheduleRefetch() {
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(seconds: 2), () => unawaited(refresh()));
  }

  void _setFeed(LiveFeedStatus feed) {
    final current = state.valueOrNull;
    if (current == null || current.feed == feed) return;
    state = AsyncData(current.copyWith(feed: feed, now: DateTime.now()));
  }

  // ── Timers ────────────────────────────────────────────────────────────────

  void _onTick() {
    final current = state.valueOrNull;
    if (current == null || _disposed) return;
    state = AsyncData(current.copyWith(now: DateTime.now()));
  }

  void _onPoll() {
    final current = state.valueOrNull;
    if (current == null || _disposed) return;
    final since = DateTime.now().difference(_lastFullRefresh);
    final shouldPoll = current.feed != LiveFeedStatus.live ? since >= _pollEvery : since >= _safetyRefreshEvery;
    if (shouldPoll) unawaited(refresh());
  }

  void _dispose() {
    _disposed = true;
    _poll?.cancel();
    _tick?.cancel();
    _resubscribe?.cancel();
    _refetchDebounce?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) unawaited(_repo.unsubscribe(ch));
  }

  LiveRidersState _empty() => LiveRidersState(
        riders: const {},
        feed: LiveFeedStatus.connecting,
        now: DateTime.now(),
      );

  static String _message(Object e) {
    if (e is TimeoutException || e is SocketException) return 'Server unreachable';
    if (e is PostgrestException) return e.message;
    if (e is AuthException) return 'Session expired. Sign in again.';
    final s = e.toString();
    return s.length > 140 ? '${s.substring(0, 137)}…' : s;
  }
}

final liveRidersProvider =
    AsyncNotifierProvider.autoDispose<LiveRidersController, LiveRidersState>(LiveRidersController.new);
