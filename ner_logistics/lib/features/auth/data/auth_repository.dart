import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../mock_data/models.dart';
import '../domain/auth_models.dart';

/// Talks to Supabase Auth and the `profiles` / `user_roles` tables.
///
/// Mirrors `src/lib/useAuth.ts` in the web app so both clients share one
/// account model: officer IDs used in the demo UI resolve to the same seed
/// emails, sign-up sends the same metadata, and the DB trigger assigns roles.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Demo officer IDs -> seed emails. Same table as the web `useAuth.ts`,
  /// plus the rider identity that only exists in the mobile app.
  static const officerIdToEmail = <String, String>{
    'NER-FO-4471': 'a.sangma@ner.gov.in',
    'NER-DO-2210': 'r.borah@kamrup.gov.in',
    'NER-DO-2281': 'r.borah@kamrup.gov.in',
    'NER-CR-0007': 's.khongsdier@ner.gov.in',
    'NER-CO-0012': 's.khongsdier@ner.gov.in',
    'NER-RD-1184': 'p.lyngdoh@ner.gov.in',
  };

  /// Officer IDs are looked up in the mapping table; emails pass through.
  static String resolveEmail(String officerIdOrEmail) {
    final trimmed = officerIdOrEmail.trim();
    return officerIdToEmail[trimmed.toUpperCase()] ?? trimmed;
  }

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<User> signIn({
    required String officerIdOrEmail,
    required String password,
  }) async {
    final email = resolveEmail(officerIdOrEmail);
    if (!email.contains('@')) {
      throw const AuthFailure(
        'Enter your official email address or a provisioned officer ID.',
        kind: AuthFailureKind.invalidCredentials,
      );
    }
    try {
      final res = await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20));
      final user = res.user;
      if (user == null) {
        throw const AuthFailure('Sign-in failed. Please try again.');
      }
      return user;
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  /// Creates the account. The `handle_new_user` DB trigger reads the metadata
  /// and creates `profiles`, `user_roles` (and `rider_profiles` for riders).
  Future<AuthResponse> signUp({
    required String officerIdOrEmail,
    required String password,
    required String fullName,
    String? district,
    String? state,
    required AppRole role,
    String? vehicleRegistration,
    String? phone,
  }) async {
    final email = resolveEmail(officerIdOrEmail);
    if (!email.contains('@')) {
      throw const AuthFailure(
        'Use your official email address to create an account.',
        kind: AuthFailureKind.invalidCredentials,
      );
    }
    try {
      return await _client.auth
          .signUp(
            email: email,
            password: password,
            data: {
              'full_name': fullName.trim(),
              if (district != null && district.trim().isNotEmpty)
                'district': district.trim(),
              if (state != null && state.trim().isNotEmpty)
                'state': state.trim(),
              'requested_role': role.dbValue,
              if (vehicleRegistration != null && vehicleRegistration.trim().isNotEmpty)
                'vehicle_registration': vehicleRegistration.trim().toUpperCase(),
              if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
            },
          )
          .timeout(const Duration(seconds: 20));
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Local session is cleared even if the network call fails.
    }
  }

  /// Loads profile + active role + district for [user]. Throws [AuthFailure]
  /// when the account is inactive or has no role, matching the web app's
  /// rejection states.
  Future<AuthUserProfile> loadProfile(User user) async {
    try {
      final results = await Future.wait([
        _client.from('profiles').select().eq('id', user.id).maybeSingle(),
        _client
            .from('user_roles')
            .select('role, district_id')
            .eq('user_id', user.id)
            .eq('is_active', true)
            .maybeSingle(),
      ]).timeout(const Duration(seconds: 20));

      final profile = results[0];
      final roleRow = results[1];

      if (profile != null && profile['is_active'] == false) {
        throw const AuthFailure(
          'This account is inactive. Contact your district administrator.',
          kind: AuthFailureKind.inactive,
        );
      }
      final role = AppRoleDb.fromDb(roleRow?['role'] as String?);
      if (role == null) {
        throw const AuthFailure(
          'No operational role is assigned to this account yet.',
          kind: AuthFailureKind.noRole,
        );
      }

      String? districtName;
      final districtId = roleRow?['district_id'] as String?;
      if (districtId != null) {
        final loc = await _client
            .from('locations')
            .select('name, district, state')
            .eq('id', districtId)
            .maybeSingle();
        districtName = (loc?['name'] ?? loc?['district'] ?? loc?['state']) as String?;
      }

      return AuthUserProfile(
        userId: user.id,
        email: user.email ?? '',
        fullName: (profile?['full_name'] as String?) ??
            (user.userMetadata?['full_name'] as String?) ??
            '',
        officerId: profile?['officer_id'] as String?,
        phone: profile?['phone'] as String?,
        department: profile?['department'] as String?,
        organization: profile?['organization'] as String?,
        region: profile?['region'] as String?,
        role: role,
        districtName: districtName,
        lastSignInAt: user.lastSignInAt == null ? null : DateTime.tryParse(user.lastSignInAt!),
      );
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw mapAuthError(e);
    }
  }

  /// Human-readable error messages (same wording as the web `normaliseAuthError`).
  static AuthFailure mapAuthError(Object error) {
    if (error is AuthFailure) return error;
    if (error is TimeoutException || error is SocketException) {
      return const AuthFailure(
        'Network error. Check your connection and try again.',
        kind: AuthFailureKind.network,
      );
    }
    final raw = error is AuthException
        ? error.message
        : error is PostgrestException
            ? error.message
            : error.toString();
    final m = raw.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return const AuthFailure(
        'Invalid credentials. Check your officer ID and password.',
        kind: AuthFailureKind.invalidCredentials,
      );
    }
    if (m.contains('email not confirmed')) {
      return const AuthFailure(
        "Your email address hasn't been verified yet. Check your inbox.",
        kind: AuthFailureKind.emailNotConfirmed,
      );
    }
    if (m.contains('user not found')) {
      return const AuthFailure(
        'No account found with those credentials.',
        kind: AuthFailureKind.invalidCredentials,
      );
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return const AuthFailure(
        'An account with this email already exists. Sign in instead.',
      );
    }
    if (m.contains('too many requests') || m.contains('rate limit')) {
      return const AuthFailure(
        'Too many attempts. Please wait a moment and try again.',
        kind: AuthFailureKind.rateLimited,
      );
    }
    if (m.contains('network') ||
        m.contains('fetch') ||
        m.contains('socket') ||
        m.contains('connection') ||
        m.contains('failed host lookup')) {
      return const AuthFailure(
        'Network error. Check your connection and try again.',
        kind: AuthFailureKind.network,
      );
    }
    return AuthFailure(raw.isEmpty ? 'Something went wrong. Please try again.' : raw);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);
