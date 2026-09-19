import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/geo_providers.dart';
import '../../../services/routing/trip_plan.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';
import '../application/ml_providers.dart';
import '../data/ml_repository.dart';
import '../domain/ml_models.dart';

// ── Chips ────────────────────────────────────────────────────────────────────

/// Marks model output so it never blends into reports or rules (WEB-007, ML-011).
class MlSourceTag extends StatelessWidget {
  final String? version;
  const MlSourceTag({super.key, this.version});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: AppColors.navy900, borderRadius: BorderRadius.circular(4)),
        child: Text('ML · ${version ?? 'model'}',
            style: AppTextStyles.chipLabel.copyWith(color: Colors.white, fontFeatures: const [])),
      );
}

class MlStateChip extends StatelessWidget {
  final MlMeta meta;
  final DateTime? cachedAt;
  const MlStateChip({super.key, required this.meta, this.cachedAt});

  @override
  Widget build(BuildContext context) {
    final saved = cachedAt;
    if (saved != null) {
      final t = saved.toLocal();
      return StatusChip(
        tone: ChipTone.muted,
        icon: Icons.cloud_off_outlined,
        label: 'Saved ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} · ${mlStateLabel(meta)}',
      );
    }
    return StatusChip(
      tone: switch (meta.state) {
        MlState.live => ChipTone.clear,
        MlState.replay => ChipTone.navy,
        _ => ChipTone.muted,
      },
      icon: meta.state == MlState.replay ? Icons.history : null,
      label: mlStateLabel(meta),
    );
  }
}

class MlBandChip extends StatelessWidget {
  final MlBand band;
  const MlBandChip({super.key, required this.band});

  @override
  Widget build(BuildContext context) => StatusChip(
        tone: switch (band) {
          MlBand.high => ChipTone.critical,
          MlBand.review => ChipTone.saffron,
          MlBand.low => ChipTone.clear,
          MlBand.noCoverage => ChipTone.muted,
        },
        icon: switch (band) {
          MlBand.high => Icons.warning_amber_rounded,
          MlBand.review => Icons.rate_review_outlined,
          MlBand.low => Icons.check,
          MlBand.noCoverage => Icons.blur_off,
        },
        label: mlBandLabel(band),
      );
}

class MlTierChip extends StatelessWidget {
  final MlTier tier;
  final bool steep;
  const MlTierChip({super.key, required this.tier, this.steep = false});

  @override
  Widget build(BuildContext context) => StatusChip(
        tone: switch (tier) {
          MlTier.alert => ChipTone.critical,
          MlTier.humanReview => ChipTone.saffron,
          MlTier.none => ChipTone.clear,
        },
        label: '${mlTierLabel(tier)}${tier == MlTier.humanReview && steep ? ' · steep' : ''}',
      );
}

/// Five-step bar; the text carries the number, the bar the gist.
class MlPercentileBar extends StatelessWidget {
  final double? percentile;
  const MlPercentileBar({super.key, required this.percentile});

  @override
  Widget build(BuildContext context) {
    final p = percentile;
    final steps = p == null ? 0 : p >= 99 ? 5 : p >= 95 ? 4 : p >= 80 ? 3 : p >= 50 ? 2 : 1;
    final color = steps >= 4 ? AppColors.signalRed700 : steps == 3 ? AppColors.saffron600 : AppColors.deepGreen700;
    return Semantics(
      label: '${topShare(p)} of corridor roads',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Container(
            width: 9,
            height: 7,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i <= steps ? color : AppColors.hairline,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        const SizedBox(width: 6),
        Text(topShare(p), style: AppTextStyles.captionSemibold),
      ]),
    );
  }
}

// ── States ───────────────────────────────────────────────────────────────────

/// Loading / signed-out / error states in words people can act on.
class MlAsync<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  const MlAsync({super.key, required this.value, required this.builder});

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(color: AppColors.navy900)),
        ),
        error: (e, _) => _Notice(
          icon: e is MlSignedOut ? Icons.lock_outline : Icons.cloud_off_outlined,
          text: e is MlSignedOut
              ? 'Sign in to see ML road risk.'
              : MlRepository.isOffline(e)
                  ? 'ML road risk unavailable offline and nothing is saved yet. Reported hazards still apply.'
                  : 'ML road risk could not be loaded: $e',
        ),
      );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => CardSurface(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.slate500),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
        ]),
      );
}

class MlCaveat extends StatelessWidget {
  final MlMeta meta;
  const MlCaveat({super.key, required this.meta});

  @override
  Widget build(BuildContext context) {
    if (!meta.hasData) return const SizedBox.shrink();
    return Text(
      '${meta.state == MlState.replay ? 'Replay of historical rainfall (${mlDate(meta.scoreDate)}) — not today\'s conditions. ' : ''}'
      'Ranked against every corridor road that day. Advisory only: verify before rerouting.',
      style: AppTextStyles.disclaimer,
    );
  }
}

// ── Route risk ───────────────────────────────────────────────────────────────

/// One route's ML summary: band, coverage, counts, riskiest point.
class MlRouteRiskTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final RouteRisk risk;
  const MlRouteRiskTile({super.key, required this.title, required this.risk, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final s = risk.summary;
    final worst = s.worst;
    return CardSurface(
      padding: const EdgeInsets.all(12),
      leftAccentColor: switch (s.band) {
        MlBand.high => AppColors.signalRed700,
        MlBand.review => AppColors.saffron600,
        MlBand.low => AppColors.deepGreen700,
        MlBand.noCoverage => AppColors.hairline,
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.bodySmallMedium),
        if (subtitle != null) Text(subtitle!, style: AppTextStyles.caption),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          MlSourceTag(version: risk.meta.modelVersion),
          MlBandChip(band: s.band),
        ]),
        const SizedBox(height: 8),
        if (s.band == MlBand.noCoverage)
          Text(
            'The model covers the Siliguri corridor, Sikkim and North Bengal. This route is outside it — '
            'rely on reported hazards here.',
            style: AppTextStyles.bodySmall,
          )
        else ...[
          Wrap(spacing: 16, runSpacing: 6, children: [
            _Fact('Model covers',
                '${(risk.coverageFraction * 100).round()}%${risk.lengthM == null ? '' : ' of ${(risk.lengthM! / 1000).round()} km'}'),
            _Fact('High risk', '${s.alerts}', color: AppColors.signalRed700),
            _Fact('Need review', '${s.reviews}', color: AppColors.saffronDark),
          ]),
          const SizedBox(height: 6),
          MlPercentileBar(percentile: s.maxPercentile),
          if (worst?.alongM != null) ...[
            const SizedBox(height: 4),
            Text(
              'Riskiest point ${(worst!.alongM! / 1000).round()} km from the start · ${mlTierLabel(worst.tier)}'
              '${worst.steep ? ' (steep terrain)' : ''}',
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Fact(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.caption),
        Text(value, style: AppTextStyles.bodySmallMedium.copyWith(color: color ?? AppColors.navy900)),
      ]);
}

/// Rider: ML risk on every route of every open shipment assigned to them.
class MlAssignedRoutesCard extends ConsumerWidget {
  const MlAssignedRoutesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MlAsync(
        value: ref.watch(myRoutesMlRiskProvider),
        builder: (data) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MlStateChip(meta: data.meta, cachedAt: data.cachedAt),
          const SizedBox(height: 10),
          if (data.routes.isEmpty)
            Text('No open shipments with a planned route.', style: AppTextStyles.bodySmall),
          for (final r in data.routes) ...[
            MlRouteRiskTile(
              title: '${r.shipmentNumber} · ${r.routeName ?? r.routeNumber ?? 'Route'}',
              subtitle: r.shipmentStatus.replaceAll('_', ' '),
              risk: r.risk,
            ),
            const SizedBox(height: 10),
          ],
          MlCaveat(meta: data.meta),
        ]),
      );
}

/// Rider active trip: the next ML-flagged segment ahead of the vehicle.
/// Advisory only — it never changes the route (ML-006).
class MlTripAdvisory extends ConsumerStatefulWidget {
  const MlTripAdvisory({super.key});

  @override
  ConsumerState<MlTripAdvisory> createState() => _MlTripAdvisoryState();
}

class _MlTripAdvisoryState extends ConsumerState<MlTripAdvisory> {
  /// Run ids whose advisory has been recorded for audit this session.
  static final _recorded = <String>{};

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(riderTripPlanProvider).valueOrNull;
    return MlAsync(
      value: ref.watch(riderTripMlRiskProvider),
      builder: (risk) {
        final ahead = risk.nextRiskAfter(plan?.vehicleM ?? 0);
        _recordOnce(risk, plan);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            MlSourceTag(version: risk.meta.modelVersion),
            MlStateChip(meta: risk.meta, cachedAt: risk.cachedAt),
          ]),
          const SizedBox(height: 10),
          if (!risk.meta.hasData)
            Text('No ML run is published. Reported hazards still apply.', style: AppTextStyles.bodySmall)
          else if (risk.summary.band == MlBand.noCoverage)
            Text('Your current trip is outside ML model coverage. Reported hazards still apply.',
                style: AppTextStyles.bodySmall)
          else if (ahead == null)
            Text('No ML-flagged segments ahead on this trip.', style: AppTextStyles.bodySmall)
          else
            CardSurface(
              padding: const EdgeInsets.all(12),
              leftAccentColor: ahead.tier == MlTier.alert ? AppColors.signalRed700 : AppColors.saffron600,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${mlTierLabel(ahead.tier)} ${formatDistance((ahead.alongM ?? 0) - (plan?.vehicleM ?? 0))} ahead',
                  style: AppTextStyles.bodySmallMedium,
                ),
                const SizedBox(height: 4),
                MlPercentileBar(percentile: ahead.riskPercentile),
                const SizedBox(height: 6),
                Text(
                  'Slow down and watch for slips or water on the road. Ask the control room before changing route.',
                  style: AppTextStyles.bodySmall,
                ),
              ]),
            ),
          const SizedBox(height: 8),
          MlCaveat(meta: risk.meta),
        ]);
      },
    );
  }

  void _recordOnce(RouteRisk risk, TripRoutePlan? plan) {
    final key = '${risk.meta.runId}:${risk.summary.band.name}';
    if (risk.meta.runId == null || risk.cachedAt != null || !_recorded.add(key)) return;
    if (risk.summary.band != MlBand.high && risk.summary.band != MlBand.review) return;
    ref.read(mlRepositoryProvider).recordSnapshot(
          context: 'advisory_shown',
          risk: risk,
          line: plan?.route.geometry,
        );
  }
}

/// Officers: every stored route with its ML summary.
class MlRoutesBoard extends ConsumerWidget {
  const MlRoutesBoard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MlAsync(
        value: ref.watch(allRoutesMlRiskProvider),
        builder: (data) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MlStateChip(meta: data.meta, cachedAt: data.cachedAt),
          const SizedBox(height: 10),
          for (final r in data.routes) ...[
            MlRouteRiskTile(title: r.routeName ?? r.routeNumber ?? 'Route', subtitle: r.routeNumber, risk: r.risk),
            const SizedBox(height: 10),
          ],
          MlCaveat(meta: data.meta),
        ]),
      );
}

/// Officers: today's highest-risk segments for their scope. Control room and
/// district officers can raise an operational alert; nothing is automatic.
class MlTopAlertsCard extends ConsumerStatefulWidget {
  final bool canPromote;
  final int? limit;
  const MlTopAlertsCard({super.key, this.canPromote = false, this.limit});

  @override
  ConsumerState<MlTopAlertsCard> createState() => _MlTopAlertsCardState();
}

class _MlTopAlertsCardState extends ConsumerState<MlTopAlertsCard> {
  String? _busy;

  Future<void> _promote(TopAlerts data, TopAlert row) async {
    setState(() => _busy = row.segment.segmentId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(mlRepositoryProvider).promote(row.segment.segmentId, runId: data.meta.runId);
      messenger?.showSnackBar(SnackBar(
          content: Text('Alert raised for ${row.segment.segmentId}'
              '${row.nearPlace == null ? '' : ' near ${row.nearPlace}'}.')));
      ref.invalidate(mlTopAlertsProvider);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not raise the alert: $e')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => MlAsync(
        value: ref.watch(mlTopAlertsProvider),
        builder: (data) {
          final rows = widget.limit == null ? data.rows : data.rows.take(widget.limit!).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              MlSourceTag(version: data.meta.modelVersion),
              MlStateChip(meta: data.meta),
            ]),
            const SizedBox(height: 6),
            if (data.meta.hasData)
              Text(
                'Top ${data.rows.length} of ${data.inTier} high-risk segments · '
                '${data.scope == 'region' ? 'region' : data.scope}',
                style: AppTextStyles.caption,
              ),
            const SizedBox(height: 8),
            if (!data.meta.hasData)
              Text('No ML run is published. Reported and rule-based alerts still apply.',
                  style: AppTextStyles.bodySmall)
            else if (rows.isEmpty)
              Text(
                'No high-risk ML segments in ${data.scope == 'region' ? 'the region' : data.scope}. '
                'The model covers the Siliguri corridor, Sikkim and North Bengal only.',
                style: AppTextStyles.bodySmall,
              ),
            for (final row in rows) ...[
              CardSurface(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(row.segment.segmentId, style: AppTextStyles.bodySmallMedium),
                      const SizedBox(height: 3),
                      MlPercentileBar(percentile: row.segment.riskPercentile),
                      const SizedBox(height: 3),
                      Text(
                        row.nearPlace == null
                            ? '${row.segment.lat.toStringAsFixed(3)}, ${row.segment.lon.toStringAsFixed(3)}'
                            : '${row.nearKm?.toStringAsFixed(1)} km from ${row.nearPlace}'
                                '${row.segment.steep ? ' · steep' : ''}',
                        style: AppTextStyles.caption,
                      ),
                    ]),
                  ),
                  if (row.promotedAlertId != null)
                    const StatusChip(tone: ChipTone.clear, icon: Icons.check, label: 'Alert raised')
                  else if (widget.canPromote)
                    OutlinedButton(
                      onPressed: _busy == null ? () => _promote(data, row) : null,
                      child: Text(_busy == row.segment.segmentId ? 'Raising…' : 'Raise alert'),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            MlCaveat(meta: data.meta),
          ]);
        },
      );
}
