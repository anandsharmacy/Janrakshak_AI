import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/connectivity_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../data/rider_repository.dart';
import '../domain/rider_location_point.dart';
import 'location_policy.dart';
import 'location_queue.dart';

enum TrackingStatus { off, starting, tracking, paused, error }

enum LocationPermissionState {
  unknown,
  always,
  whileInUse,
  denied,
  deniedForever,
  serviceDisabled,
}

class RiderTrackingState {
  final TrackingStatus status;
  final LocationPermissionState permission;

  /// Last fix that passed the policy and was queued/uploaded.
  final RiderLocationPoint? lastFix;
  final LocationDecision? lastDecision;
  final DateTime? lastSyncAt;
  final DateTime? startedAt;
  final int queued;
  final int sentSinceStart;
  final String? shipmentId;
  final String? error;
  final bool uploading;
  final bool online;

  const RiderTrackingState({
    this.status = TrackingStatus.off,
    this.permission = LocationPermissionState.unknown,
    this.lastFix,
    this.lastDecision,
    this.lastSyncAt,
    this.startedAt,
    this.queued = 0,
    this.sentSinceStart = 0,
    this.shipmentId,
    this.error,
    this.uploading = false,
    this.online = true,
  });

  bool get isSharing => status == TrackingStatus.tracking || status == TrackingStatus.paused;

  RiderTrackingState copyWith({
    TrackingStatus? status,
    LocationPermissionState? permission,
    RiderLocationPoint? lastFix,
    LocationDecision? lastDecision,
    DateTime? lastSyncAt,
    DateTime? startedAt,
    int? queued,
    int? sentSinceStart,
    String? shipmentId,
    Object? error = _sentinel,
    bool? uploading,
    bool? online,
  }) =>
      RiderTrackingState(
        status: status ?? this.status,
        permission: permission ?? this.permission,
        lastFix: lastFix ?? this.lastFix,
        lastDecision: lastDecision ?? this.lastDecision,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        startedAt: startedAt ?? this.startedAt,
        queued: queued ?? this.queued,
        sentSinceStart: sentSinceStart ?? this.sentSinceStart,
        shipmentId: shipmentId ?? this.shipmentId,
        error: identical(error, _sentinel) ? this.error : error as String?,
        uploading: uploading ?? this.uploading,
        online: online ?? this.online,
      );

  static const _sentinel = Object();
}

/// Captures the rider's GPS position, throttles it through [LocationPolicy],
/// queues it durably, and uploads it to Supabase in batches.
///
/// Battery / data budget:
///  * platform stream with 10 m distance filter (fused provider does the work)
///  * policy drops stationary / duplicate fixes; heartbeat every 60 s keeps
///    the map's "last seen" honest
///  * uploads are batched (≤200 points/RPC) and retried with exponential
///    back-off; the queue survives restarts and connectivity gaps
///  * Android runs a foreground service so tracking continues with the
///    screen off; iOS uses background location updates
class RiderTrackingController extends Notifier<RiderTrackingState> {
  static const _flushEvery = Duration(seconds: 15);
  static const _batchSize = 200;
  static const _maxBackoff = Duration(minutes: 2);

  final _uuid = const Uuid();
  StreamSubscription<Position>? _positions;
  Timer? _heartbeatTimer;
  Timer? _flushTimer;
  LocationQueue? _queue;
  Future<LocationQueue>? _queueInit;
  LocationPolicy _policy = const LocationPolicy();
  bool _flushing = false;
  int _failures = 0;
  DateTime? _nextRetryAt;

  RiderRepository get _repo => ref.read(riderRepositoryProvider);

  @override
  RiderTrackingState build() {
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
      final online = next.valueOrNull ?? true;
      final wasOnline = prev?.valueOrNull ?? true;
      state = state.copyWith(online: online);
      if (online && !wasOnline) {
        _failures = 0;
        _nextRetryAt = null;
        unawaited(flush());
      }
    });
    // Signing out must always stop sharing.
    ref.listen(authControllerProvider, (_, next) {
      if (next.valueOrNull == null && state.isSharing) unawaited(stop(reportDuty: false));
    });
    ref.onDispose(_teardown);
    unawaited(_ensureQueue().then((q) {
      state = state.copyWith(queued: q.length, lastSyncAt: q.lastSyncAt);
    }));
    return const RiderTrackingState();
  }

  Future<LocationQueue> _ensureQueue() {
    if (_queue != null) return Future.value(_queue);
    return _queueInit ??= SharedPreferences.getInstance().then((prefs) {
      return _queue = LocationQueue(prefs);
    });
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Starts (or restarts) continuous sharing. [shipmentId] is attached to
  /// every fix so officers see what the rider is carrying.
  Future<void> start({String? shipmentId, bool paused = false}) async {
    final queue = await _ensureQueue();
    state = state.copyWith(
      status: TrackingStatus.starting,
      error: null,
      shipmentId: shipmentId ?? state.shipmentId,
      queued: queue.length,
    );

    final permission = await _ensurePermission();
    state = state.copyWith(permission: permission);
    if (permission != LocationPermissionState.always &&
        permission != LocationPermissionState.whileInUse) {
      state = state.copyWith(status: TrackingStatus.error, error: _permissionMessage(permission));
      return;
    }

    _policy = paused ? const LocationPolicy.paused() : const LocationPolicy();
    await _positions?.cancel();
    try {
      _positions = Geolocator.getPositionStream(locationSettings: _settings(paused)).listen(
        _onPosition,
        onError: (Object e) {
          state = state.copyWith(error: 'GPS stream error: $e');
        },
      );
    } catch (e) {
      state = state.copyWith(status: TrackingStatus.error, error: 'Could not start GPS: $e');
      return;
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_policy.heartbeat, (_) => unawaited(_heartbeat()));
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushEvery, (_) => unawaited(flush()));

    state = state.copyWith(
      status: paused ? TrackingStatus.paused : TrackingStatus.tracking,
      startedAt: state.startedAt ?? DateTime.now(),
      error: null,
    );

    unawaited(_setDuty(true));
    unawaited(captureNow());
  }

  /// Switches between the full-rate and low-rate profiles without a gap.
  Future<void> setPaused(bool paused) async {
    if (!state.isSharing) return;
    if (paused && state.status == TrackingStatus.paused) return;
    if (!paused && state.status == TrackingStatus.tracking) return;
    await start(paused: paused);
  }

  /// Stops sharing, flushes what it can, and marks the rider off duty.
  Future<void> stop({bool reportDuty = true}) async {
    _teardown();
    state = state.copyWith(status: TrackingStatus.off, startedAt: null, error: null);
    if (state.online) await flush();
    if (reportDuty) await _setDuty(false);
  }

  /// Manual "send check-in": one fresh fix, bypassing the throttle.
  Future<void> captureNow() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 20));
      await _accept(_point(position), LocationDecision.accept);
    } catch (e) {
      state = state.copyWith(error: 'Could not get a GPS fix: ${_short(e)}');
    }
  }

  /// Uploads the queue in batches. Safe to call at any time.
  Future<void> flush() async {
    final queue = await _ensureQueue();
    if (queue.isEmpty || _flushing || !state.online) return;
    final now = DateTime.now();
    if (_nextRetryAt != null && now.isBefore(_nextRetryAt!)) return;

    _flushing = true;
    state = state.copyWith(uploading: true);
    try {
      while (queue.isNotEmpty) {
        final batch = queue.take(_batchSize);
        await _repo.syncLocations(batch);
        await queue.removeByIds(batch.map((p) => p.clientId));
        state = state.copyWith(
          queued: queue.length,
          sentSinceStart: state.sentSinceStart + batch.length,
          lastSyncAt: DateTime.now(),
          error: null,
        );
      }
      await queue.markSynced();
      _failures = 0;
      _nextRetryAt = null;
    } catch (e) {
      _failures++;
      final backoffSec = math.min(_maxBackoff.inSeconds, 5 * math.pow(2, _failures - 1).toInt());
      _nextRetryAt = DateTime.now().add(Duration(seconds: backoffSec));
      state = state.copyWith(error: _uploadMessage(e), queued: queue.length);
    } finally {
      _flushing = false;
      state = state.copyWith(uploading: false);
    }
  }

  void clearError() => state = state.copyWith(error: null);

  /// User-initiated retry: drops the back-off and uploads immediately.
  Future<void> retryNow() async {
    _failures = 0;
    _nextRetryAt = null;
    state = state.copyWith(error: null);
    await flush();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _onPosition(Position position) {
    final point = _point(position);
    final decision = _policy.evaluate(candidate: point, lastAccepted: state.lastFix);
    state = state.copyWith(lastDecision: decision);
    if (decision.accepted) {
      unawaited(_accept(point.copyWith(heartbeat: decision == LocationDecision.acceptHeartbeat), decision));
    }
  }

  Future<void> _heartbeat() async {
    final last = state.lastFix;
    if (last != null && DateTime.now().toUtc().difference(last.recordedAt) < _policy.heartbeat) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 20));
      await _accept(_point(position, heartbeat: true), LocationDecision.acceptHeartbeat);
    } catch (_) {
      // Heartbeat is best-effort; the stream will deliver the next real fix.
    }
  }

  Future<void> _accept(RiderLocationPoint point, LocationDecision decision) async {
    final queue = await _ensureQueue();
    await queue.enqueue(point);
    state = state.copyWith(lastFix: point, lastDecision: decision, queued: queue.length);
    if (state.online) unawaited(flush());
  }

  RiderLocationPoint _point(Position p, {bool heartbeat = false}) => RiderLocationPoint.fromPosition(
        p,
        clientId: _uuid.v4(),
        shipmentId: state.shipmentId,
        heartbeat: heartbeat,
      );

  Future<void> _setDuty(bool onDuty) async {
    try {
      await _repo.setDuty(onDuty);
    } catch (e) {
      debugPrint('set_rider_duty($onDuty) failed: $e');
    }
  }

  Future<LocationPermissionState> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always => LocationPermissionState.always,
      LocationPermission.whileInUse => LocationPermissionState.whileInUse,
      LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      LocationPermission.denied => LocationPermissionState.denied,
      LocationPermission.unableToDetermine => LocationPermissionState.denied,
    };
  }

  LocationSettings _settings(bool paused) {
    final accuracy = paused ? LocationAccuracy.medium : LocationAccuracy.high;
    final distance = paused ? 50 : 10;
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        intervalDuration: Duration(seconds: paused ? 30 : 5),
        // Keeps the fix stream alive when the app is backgrounded / screen off.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Janrakshak AI · sharing location',
          notificationText: 'Your position is visible to the control room while on duty.',
          notificationChannelName: 'Location sharing',
          enableWakeLock: true,
          setOngoing: true,
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        ),
      );
    }
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: distance,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distance);
  }

  void _teardown() {
    _positions?.cancel();
    _positions = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  static String _permissionMessage(LocationPermissionState p) => switch (p) {
        LocationPermissionState.serviceDisabled => 'Turn on Location Services to share your position.',
        LocationPermissionState.deniedForever =>
          'Location permission is blocked. Enable it for Janrakshak AI in Settings.',
        LocationPermissionState.denied => 'Location permission is required to share your position.',
        _ => 'Location permission is required.',
      };

  static String _uploadMessage(Object e) {
    if (e is TimeoutException || e is SocketException) {
      return 'Server unreachable — positions are queued and will sync automatically.';
    }
    if (e is PostgrestException) {
      final m = e.message.toLowerCase();
      if (m.contains('rider role')) return 'This account is not a rider. Location sharing is disabled.';
      if (m.contains('not authenticated') || e.code == '401') return 'Session expired. Sign in again.';
      return 'Upload rejected: ${e.message}';
    }
    if (e is AuthException) return 'Session expired. Sign in again.';
    return 'Upload failed — will retry. (${_short(e)})';
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 117)}…' : s;
  }
}

final riderTrackingProvider =
    NotifierProvider<RiderTrackingController, RiderTrackingState>(RiderTrackingController.new);
