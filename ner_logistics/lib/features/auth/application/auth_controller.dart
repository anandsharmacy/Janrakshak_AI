import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../mock_data/models.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// Authentication state for the whole app.
///
/// * `AsyncLoading`            → restoring the persisted session at start-up
/// * `AsyncData(null)`         → signed out
/// * `AsyncData(profile)`      → signed in, role loaded, router may proceed
///
/// Sign-in / sign-up errors are thrown as [AuthFailure] to the caller (the
/// login form shows them inline); the state itself never becomes an error, so
/// the router treats any failure as "signed out".
class AuthController extends AsyncNotifier<AuthUserProfile?> {
  StreamSubscription<AuthState>? _sub;
  String? _loadingUserId;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthUserProfile?> build() async {
    _sub?.cancel();
    _sub = _repo.onAuthStateChange.listen(_onAuthEvent);
    ref.onDispose(() => _sub?.cancel());

    final session = _repo.currentSession;
    if (session == null) return null;
    try {
      return await _loadFor(session.user);
    } on AuthFailure {
      // Stale session for an account that lost its role/activation.
      await _repo.signOut();
      return null;
    }
  }

  Future<void> _onAuthEvent(AuthState event) async {
    switch (event.event) {
      case AuthChangeEvent.signedOut:
      case AuthChangeEvent.userDeleted:
        state = const AsyncData(null);
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        final user = event.session?.user;
        if (user == null) return;
        final current = state.valueOrNull;
        if (current?.userId == user.id || _loadingUserId == user.id) return;
        try {
          state = AsyncData(await _loadFor(user));
        } on AuthFailure {
          await _repo.signOut();
          state = const AsyncData(null);
        }
      default:
        break;
    }
  }

  Future<AuthUserProfile> _loadFor(User user) async {
    _loadingUserId = user.id;
    try {
      return await _repo.loadProfile(user);
    } finally {
      _loadingUserId = null;
    }
  }

  /// Signs in and loads the profile. Throws [AuthFailure] on any problem and
  /// guarantees the session is cleared in that case.
  Future<AuthUserProfile> signIn({
    required String officerIdOrEmail,
    required String password,
  }) async {
    try {
      final user = await _repo.signIn(
        officerIdOrEmail: officerIdOrEmail,
        password: password,
      );
      final profile = await _loadFor(user);
      state = AsyncData(profile);
      return profile;
    } on AuthFailure {
      await _repo.signOut();
      state = const AsyncData(null);
      rethrow;
    } catch (e) {
      await _repo.signOut();
      state = const AsyncData(null);
      throw AuthRepository.mapAuthError(e);
    }
  }

  /// Creates the account. Returns true when a session was issued immediately
  /// (email confirmation disabled, as in the local stack) — the auth event
  /// then loads the profile and the router redirects. Returns false when the
  /// user must confirm their email first.
  Future<bool> signUp({
    required String officerIdOrEmail,
    required String password,
    required String fullName,
    String? district,
    String? state,
    required AppRole role,
    String? vehicleRegistration,
    String? phone,
  }) async {
    final res = await _repo.signUp(
      officerIdOrEmail: officerIdOrEmail,
      password: password,
      fullName: fullName,
      district: district,
      state: state,
      role: role,
      vehicleRegistration: vehicleRegistration,
      phone: phone,
    );
    final user = res.user;
    if (res.session == null || user == null) return false;
    try {
      // `this.` — the `state` parameter (address state) shadows the notifier's state.
      this.state = AsyncData(await _loadFor(user));
      return true;
    } on AuthFailure {
      await _repo.signOut();
      this.state = const AsyncData(null);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(null);
  }

  /// Re-reads profile/role (e.g. after editing the profile).
  Future<void> refreshProfile() async {
    final user = _repo.currentUser;
    if (user == null) return;
    state = AsyncData(await _loadFor(user));
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthUserProfile?>(AuthController.new);

/// Role of the signed-in user, or null. Drives the GoRouter redirect.
final authRoleProvider =
    Provider<AppRole?>((ref) => ref.watch(authControllerProvider).valueOrNull?.role);

/// False only while the persisted session is being restored at start-up.
final authReadyProvider =
    Provider<bool>((ref) => !ref.watch(authControllerProvider).isLoading);

/// Convenience: the current profile (null when signed out / loading).
final currentProfileProvider =
    Provider<AuthUserProfile?>((ref) => ref.watch(authControllerProvider).valueOrNull);
