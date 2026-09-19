import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Connection settings (override in tests / flavours).
final supabaseConfigProvider =
    Provider<SupabaseConfig>((_) => SupabaseConfig.fromEnvironment());

/// The single Supabase client. `Supabase.initialize` runs in `main()` before
/// `runApp`, so the instance is always ready by the time a provider reads it.
/// Screens never touch this directly — repositories do.
final supabaseClientProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);
