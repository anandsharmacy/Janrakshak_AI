import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/demo/demo_mode.dart';
import 'core/supabase/supabase_providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — field officers use devices one-handed in the field.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Edge-to-edge display — content draws behind status bar.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // Same Supabase project as the web dashboards. Sessions persist on-device
  // (SDK secure storage) and refresh automatically; PKCE for any email links.
  await DemoMode.load();

  final config = SupabaseConfig.fromEnvironment();
  try {
    await Supabase.initialize(
      url: config.url,
      anonKey: config.publishableKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  } catch (e) {
    runApp(_ConfigErrorApp(config: config, error: e));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [supabaseConfigProvider.overrideWithValue(config)],
      child: const NerLogisticsApp(),
    ),
  );
}

class NerLogisticsApp extends ConsumerWidget {
  const NerLogisticsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Janrakshak AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,

      // GoRouter integration
      routerConfig: router,

      // Localisation — English default; Hindi, Assamese, Bengali wired.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('as'),
        Locale('bn'),
      ],
    );
  }
}

/// Shown only when `Supabase.initialize` itself fails (malformed URL/key).
/// Network problems are NOT this — they surface inside the app as retry states.
class _ConfigErrorApp extends StatelessWidget {
  final SupabaseConfig config;
  final Object error;
  const _ConfigErrorApp({required this.config, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('Backend configuration error',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Could not initialise Supabase for ${config.url}.\n\n$error'),
                const SizedBox(height: 16),
                const Text(
                  'Pass --dart-define=SUPABASE_URL=… and '
                  '--dart-define=SUPABASE_PUBLISHABLE_KEY=… (see README.md).',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
