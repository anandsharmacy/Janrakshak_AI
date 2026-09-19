import 'package:supabase_flutter/supabase_flutter.dart';

// The publishable key is public by design (RLS is the security boundary), so it is safe to commit.
const supabaseUrl = 'https://sjcqwxthimfuxmrodsbs.supabase.co';
const supabasePublishableKey = 'sb_publishable_trfIbiBzVtUGLSEDv0EKog_h0WqqvpQ';

/// Idempotent: the WorkManager task may run in the main isolate (already initialised) or a fresh one.
Future<void> ensureSupabase() async {
  try {
    Supabase.instance.client;
  } catch (_) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  }
}
