import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/feed.dart';
import '../../data/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../trip_planner/trip_store.dart';
import 'alerts_provider.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(alertFilterProvider);
    final items = ref.watch(filteredAlertsProvider);
    final me = ref.watch(myPlaceProvider);
    final hasTrip = ref.watch(activeRouteProvider) != null;

    final banners = <Widget>[
      if (ref.watch(hazardFeedProvider).value?.stale ?? false)
        const StatusBanner(lead: 'Live risk data unavailable.', text: 'Showing the last cached update.'),
      if (filter == AlertFilter.region && me.hasValue && me.value?.region == null)
        const StatusBanner(lead: 'Region unknown.', text: 'Turn on location to filter by your region; showing all alerts.'),
    ];

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const ScreenHeader(eyebrow: 'Prioritised advisories', title: 'Alerts'),
        const SizedBox(height: 12),
        SegmentedButton<AlertFilter>(
          segments: [for (final f in AlertFilter.values) ButtonSegment(value: f, label: Text(f.label, textAlign: TextAlign.center))],
          selected: {filter},
          showSelectedIcon: false,
          onSelectionChanged: (v) => ref.read(alertFilterProvider.notifier).set(v.first),
        ),
        for (final b in banners) Padding(padding: const EdgeInsets.only(top: 12), child: b),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              const Icon(Icons.notifications_off_outlined, size: 48, color: AppTheme.mutedOnDark),
              const SizedBox(height: 8),
              Text(filter == AlertFilter.trip && !hasTrip ? 'No active trip.' : 'No alerts here right now.'),
              if (filter == AlertFilter.trip && !hasTrip) ...[
                const SizedBox(height: 12),
                PillButton(label: 'Plan a trip', icon: Icons.alt_route_outlined, outlined: true, onPressed: () => context.go('/home/trip')),
              ],
            ]),
          )
        else
          for (final h in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: AlertCard(h)),
      ]),
    );
  }
}
