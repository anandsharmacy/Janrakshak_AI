import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/alerts/alerts_provider.dart';
import 'features/alerts/alerts_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/contacts/contacts_screen.dart';
import 'features/home/home_screen.dart';
import 'features/map/map_screen.dart';
import 'features/report/report_screen.dart';
import 'features/report/report_service.dart';
import 'features/trip_planner/navigation_screen.dart';
import 'features/trip_planner/trip_planner_screen.dart';

GoRouter createRouter({
  required Listenable refresh,
  required bool Function() signedIn,
}) {
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (_, state) {
      final onAuth = state.matchedLocation == '/auth';
      if (!signedIn()) return onAuth ? null : '/auth';
      return onAuth ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'trip',
                    builder: (_, _) => const TripPlannerScreen(),
                    routes: [
                      // Full screen: pushed over the shell so the bottom navigation bar is hidden while driving.
                      GoRoute(
                        path: 'navigate',
                        parentNavigatorKey: rootKey,
                        builder: (_, _) => const NavigationScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/report', builder: (_, _) => const ReportScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                builder: (_, _) => const ContactsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class AppShell extends ConsumerWidget {
  const AppShell(this.shell, {super.key});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // App-lifetime background work: flush the offline report queue on reconnect, watch for hazards near GPS / active trip.
    ref.watch(reportFlushProvider);
    ref.watch(alertWatcherProvider);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            label: 'Contacts',
          ),
        ],
      ),
    );
  }
}
