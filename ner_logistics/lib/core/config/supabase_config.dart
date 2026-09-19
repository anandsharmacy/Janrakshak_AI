import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Supabase connection settings for the mobile app.
///
/// The Flutter app talks to the SAME Supabase project as the web dashboards
/// (`web/.../App Development/supabase`). Override at build time:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=http://192.168.1.20:54321 \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// Defaults target the local `supabase start` stack:
///   - Android emulator reaches the host machine at 10.0.2.2
///   - iOS simulator / desktop reach it at 127.0.0.1
/// A physical phone needs the laptop's LAN IP via --dart-define.
///
/// Only the *publishable* key ever ships in the app. RLS is the security
/// boundary; the service-role key stays in Edge Functions.
class SupabaseConfig {
  final String url;
  final String publishableKey;

  const SupabaseConfig({required this.url, required this.publishableKey});

  /// Local publishable key issued by the Supabase CLI for `supabase start`.
  /// Identical to VITE_SUPABASE_PUBLISHABLE_KEY in the web .env.local files.
  static const localPublishableKey =
      'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

  static const _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const _envKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  factory SupabaseConfig.fromEnvironment() {
    final url = _envUrl.isNotEmpty ? _envUrl : _defaultLocalUrl();
    final key = _envKey.isNotEmpty ? _envKey : localPublishableKey;
    return SupabaseConfig(url: url, publishableKey: key);
  }

  static String _defaultLocalUrl() {
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:54321';
    return 'http://127.0.0.1:54321';
  }

  bool get isLocal =>
      url.contains('127.0.0.1') ||
      url.contains('localhost') ||
      url.contains('10.0.2.2');

  @override
  String toString() => 'SupabaseConfig($url, key=${publishableKey.substring(0, 14)}…)';
}
