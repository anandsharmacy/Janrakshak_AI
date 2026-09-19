import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'data/auth.dart';

import 'data/offline_tiles.dart';
import 'data/region_data.dart';
import 'data/store.dart';
import 'data/supabase_config.dart';
import 'features/alerts/alerts_provider.dart';
import 'features/report/report_service.dart';
import 'router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  await Future.wait([RegionData.load(), Store.init()]);
  await OfflineTiles.init();
  await ensureSupabase();
  await Workmanager().initialize(callbackDispatcher);
  await initNotifications();
  // retry: null -> a failed provider (e.g. geocoder offline) surfaces its error once instead of auto-retrying forever.
  final auth = Supabase.instance.client.auth;
  final router = createRouter(
    refresh: AuthRefresh(auth.onAuthStateChange),
    signedIn: () => auth.currentSession != null,
  );
  runApp(ProviderScope(retry: (_, _) => null, child: JanRakshakApp(router)));
}

class JanRakshakApp extends StatelessWidget {
  const JanRakshakApp(this.router, {super.key});
  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'JanRakshak AI',
        theme: AppTheme.dark,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      );
}
