import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/demo/demo_mode.dart';
import 'mock_data/models.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/onboarding/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/field_officer/field_officer_shell.dart';
import 'features/district_officer/district_officer_shell.dart';
import 'features/control_room/control_room_shell.dart';
import 'features/rider/rider_shell.dart';

export 'features/auth/application/auth_controller.dart' show authRoleProvider;

// ── Route paths ───────────────────────────────────────────────────────────
class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const fieldDashboard = '/field/dashboard';
  static const fieldTrip = '/field/trip';
  static const fieldTasks = '/field/tasks';
  static const fieldReport = '/field/report';
  static const fieldReports = '/field/reports';
  static const fieldAlerts = '/field/alerts';
  static const fieldRouteStatus = '/field/route-status';
  static const fieldLogistics = '/field/logistics';
  static const districtDashboard = '/district/dashboard';
  static const controlDashboard = '/control/dashboard';
  static const riderDashboard = '/rider/dashboard';

  static String dashboardFor(AppRole role) => switch (role) {
        AppRole.field => fieldDashboard,
        AppRole.district => districtDashboard,
        AppRole.control => controlDashboard,
        AppRole.rider => riderDashboard,
      };
}

// ── Router ────────────────────────────────────────────────────────────────
// Auth is the single source of truth: the Supabase session + DB role decide
// which shell is shown. The router is rebuilt when the role changes, which is
// what makes sign-in / sign-out navigate without any manual `go()` calls.
final routerProvider = Provider<GoRouter>((ref) {
  final authRole = ref.watch(authRoleProvider);
  final authReady = ref.watch(authReadyProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final loggedIn = authRole != null;
      final onSplash = state.matchedLocation == AppRoutes.splash;
      final onLogin = state.matchedLocation == AppRoutes.login;

      // Session still being restored — hold on the splash screen.
      if (!authReady) return onSplash ? null : AppRoutes.splash;

      // Not logged in — allow splash and login only
      if (!loggedIn && !onSplash && !onLogin) return AppRoutes.splash;

      // Already logged in — redirect away from splash/login
      if (loggedIn && (onSplash || onLogin)) return AppRoutes.dashboardFor(authRole);

      // Logged in but on another role's shell — send to the right one.
      if (loggedIn) {
        final expected = AppRoutes.dashboardFor(authRole);
        final prefix = expected.split('/')[1];
        if (!state.matchedLocation.startsWith('/$prefix/')) return expected;
      }

      return null; // No redirect needed
    },
    routes: _buildRoutes(),
  );
});

List<RouteBase> _buildRoutes() {
  return [
    // ── Onboarding ─────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => SplashScreen(
        onLogIn: () => context.go('/login?m=signin'),
        onCreateAccount: () => context.go('/login?m=create'),
      ),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) {
        final mode = state.uri.queryParameters['m'];
        return LoginScreen(
          createMode: mode == 'create',
          onBack: () => context.go('/'),
        );
      },
    ),

    // Each shell is keyed on demo mode so switching it rebuilds the screens
    // from the (now empty or populated) sample data.
    // ── Field Officer shell ─────────────────────────────────────
    GoRoute(
      path: AppRoutes.fieldDashboard,
      builder: (context, state) => Consumer(
        builder: (ctx, ref, _) => KeyedSubtree(
          key: ValueKey(ref.watch(demoModeProvider)),
          child: FieldOfficerShell(
            onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ),
      ),
    ),

    // ── District Officer shell ──────────────────────────────────
    GoRoute(
      path: AppRoutes.districtDashboard,
      builder: (context, state) => Consumer(
        builder: (ctx, ref, _) => KeyedSubtree(
          key: ValueKey(ref.watch(demoModeProvider)),
          child: DistrictOfficerShell(
            onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ),
      ),
    ),

    // ── Control Room shell ──────────────────────────────────────
    GoRoute(
      path: AppRoutes.controlDashboard,
      builder: (context, state) => Consumer(
        builder: (ctx, ref, _) => KeyedSubtree(
          key: ValueKey(ref.watch(demoModeProvider)),
          child: ControlRoomShell(
            onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ),
      ),
    ),

    // ── Logistics Rider shell ───────────────────────────────────
    GoRoute(
      path: AppRoutes.riderDashboard,
      builder: (context, state) => Consumer(
        builder: (ctx, ref, _) => KeyedSubtree(
          key: ValueKey(ref.watch(demoModeProvider)),
          child: RiderShell(
            onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ),
      ),
    ),
  ];
}
