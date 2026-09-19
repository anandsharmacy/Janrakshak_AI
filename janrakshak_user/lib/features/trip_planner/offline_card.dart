import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/offline_tiles.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'offline_controller.dart';
import 'trip_controller.dart';

String formatBytes(num b) => b < 1e6 ? '${(b / 1e3).round()} KB' : '${(b / 1e6).toStringAsFixed(b < 1e8 ? 1 : 0)} MB';

/// Shown once From and To are chosen: downloads map tiles along the route to the destination.
class OfflineCard extends ConsumerWidget {
  const OfflineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(offlineControllerProvider);
    final c = ref.read(offlineControllerProvider.notifier);
    final areas = ref.watch(offlineAreasProvider).value ?? const [];
    final t = Theme.of(context).textTheme;
    final total = areas.fold<int>(0, (a, e) => a + e.bytes);

    Future<void> start() async {
      final trip = ref.read(tripControllerProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(content: Text('Planning the offline area...')));
      final plan = await c.plan();
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog( // pop with this context: the dialog is on the root navigator, the card's is not
          title: const Text('Download offline map?'),
          content: Text('About ${plan.count} map tiles (roughly ${(plan.estimatedBytes / 1e6).toStringAsFixed(0)} MB) along your route '
              'to ${trip.to!.label}, street detail up to zoom ${plan.maxZoom}. This uses mobile data, so Wi-Fi is best.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Download')),
          ],
        ),
      );
      if (ok == true) await c.download(plan, '${trip.from!.label} → ${trip.to!.label}');
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bgRaised, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Offline map'),
        const SizedBox(height: 6),
        if (!offlineMapsEnabled)
          const StatusBanner(
            lead: 'Offline maps are not set up in this build.',
            text: 'They need your own hosted map file (PMTiles). Build with PMTILES_URL set; see the README.',
            icon: Icons.map_outlined,
          )
        else if (s.busy) ...[
          LinearProgressIndicator(value: s.total == 0 ? null : s.done / s.total),
          const SizedBox(height: 6),
          Text('Downloading ${s.done} / ${s.total} tiles (${formatBytes(s.bytes)})', style: t.bodySmall),
          const SizedBox(height: 6),
          PillButton(label: 'Cancel', icon: Icons.close_outlined, outlined: true, onPressed: c.cancel),
        ] else ...[
          Text('Save the map along your route to the destination so navigation still shows it without signal.', style: t.bodySmall),
          const SizedBox(height: 8),
          PillButton(label: 'Download map to destination', icon: Icons.download_outlined, onPressed: start),
        ],
        if (s.message != null && !s.busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: StatusBanner(
              lead: s.isError ? 'Download failed.' : 'Done.',
              text: s.message!,
              color: s.isError ? AppColors.statusCritical : AppColors.statusOk,
              icon: s.isError ? Icons.error_outline : Icons.check_circle_outline,
            ),
          ),
        if (areas.isNotEmpty && !s.busy) ...[
          const SizedBox(height: 8),
          for (final a in areas.reversed.take(3))
            Text('${a.label} · ${a.tiles} tiles · ${formatBytes(a.bytes)}', style: t.bodySmall),
          Row(children: [
            Expanded(child: Text('${formatBytes(total)} saved in total', style: t.labelMedium?.copyWith(color: AppTheme.mutedOnDark))),
            TextButton(onPressed: c.clear, child: const Text('Delete all')),
          ]),
        ],
      ]),
    );
  }
}
