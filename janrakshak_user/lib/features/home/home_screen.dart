import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import '../../data/auth.dart';
import '../../data/providers.dart';
import '../../data/taxonomy.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../alerts/alerts_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(myPlaceProvider);
    final online = ref.watch(onlineProvider).value ?? true;
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final trips = ref.watch(tripCountProvider).value ?? 0;
    final alerts = ref.watch(regionAlertsProvider);
    final critical = alerts.where((h) => h.severity == Severity.critical).length;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final email = ref.watch(sessionProvider).value?.user.email;

    final stats = [
      (Icons.notifications_active_outlined, '${alerts.length}', 'Active alerts', '/alerts'),
      (Icons.crisis_alert_outlined, '$critical', 'Critical', '/alerts'),
      (Icons.outbox_outlined, '$pending', 'Reports waiting', '/report'),
      (Icons.alt_route_outlined, '$trips', 'Saved trips', '/home/trip'),
    ];
    Widget card((IconData, String, String, String) s) =>
        StatCard(icon: s.$1, value: s.$2, label: s.$3, onTap: () => context.go(s.$4));

    final p = place.value;
    final region = p?.region;
    final sub = [if (p?.district != null) p!.district!, if (p?.state != null) p!.state!].join(', ');

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        ScreenHeader(
          eyebrow: 'Active region',
          title: region ?? (place.isLoading ? 'Locating...' : 'India'),
          trailing: PopupMenuButton<void>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            color: AppColors.bgRaised,
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(email ?? 'Signed in')),
              PopupMenuItem(
                onTap: () => Supabase.instance.client.auth.signOut(),
                child: const Row(children: [Icon(Icons.logout_outlined), SizedBox(width: 8), Text('Sign out')]),
              ),
            ],
          ),
        ),
        if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: AppTheme.mutedOnDark)),
        if (!online)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: StatusBanner(lead: 'Live risk data unavailable.', text: 'Showing last cached update.')),
        if (place.hasValue && p == null) ...[
          const SizedBox(height: 12),
          const StatusBanner(lead: 'Location is off.', text: 'Enable it to see alerts and contacts for your area.'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
                label: 'Enable location', icon: Icons.my_location_outlined, outlined: true,
                onPressed: () => ref.invalidate(positionProvider)),
          ),
        ],
        if (pending > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: StatusBanner(
                lead: '$pending report${pending == 1 ? '' : 's'} waiting.',
                text: 'They will send automatically when you are back online.',
                icon: Icons.cloud_off_outlined),
          ),
        const SizedBox(height: 16),
        if (wide)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 128),
            itemCount: stats.length,
            itemBuilder: (_, i) => card(stats[i]),
          )
        else
          SizedBox(
            height: 152,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: stats.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(width: 140, child: card(stats[i])),
            ),
          ),
        const SizedBox(height: 24),
        const Eyebrow('Main menu'),
        const SizedBox(height: 8),
        PillButton(label: 'Report an incident', icon: Icons.edit_note_outlined, expand: true, onPressed: () => context.go('/report')),
        const SizedBox(height: 8),
        _MenuTile(Icons.map_outlined, 'Disaster map', 'Live risk, 1-week and 1-month trends', () => context.go('/map')),
        _MenuTile(Icons.alt_route_outlined, 'Trip planner', 'Check a route and get a safe diversion', () => context.go('/home/trip')),
        _MenuTile(Icons.contacts_outlined, 'Emergency contacts', 'SOS, field officers, hospitals, police', () => context.go('/contacts')),
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(children: [
            const Expanded(child: Eyebrow('Latest in your region')),
            TextButton(onPressed: () => context.go('/alerts'), child: const Text('See all')),
          ]),
          const SizedBox(height: 4),
          for (final h in alerts.take(2)) Padding(padding: const EdgeInsets.only(bottom: 12), child: AlertCard(h)),
        ],
      ]),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LightCard(
          onTap: onTap,
          child: Builder(builder: (context) {
            final t = Theme.of(context).textTheme;
            return Row(children: [
              Icon(icon, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.titleLarge),
                  Text(subtitle, style: t.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right_outlined),
            ]);
          }),
        ),
      );
}
