import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../mock_data/models.dart';
import '../../../services/geo_providers.dart';
import '../../../services/routing/trip_plan.dart';
import '../../../shared/map/trip_route_map.dart';
import '../../../shared/widgets/map_legend.dart';
import '../../../shared/widgets/trip_widgets.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';
import 'trip_copy.dart';

/// RouteScreen — 4-phase active trip state machine.
/// Phases: active → interrupt → calculating → rerouted
/// Matches React RouteScreen / ActiveSheet / CalculatingSheet / ReroutedSheet.
class RouteScreen extends ConsumerStatefulWidget {
  final TripPhase phase;
  final bool postReroute;
  final bool riskUpgraded;
  final bool isOffline;
  final ValueChanged<TripPhase> onPhaseChange;
  final VoidCallback onRerouted;
  final VoidCallback onNotNow;
  final VoidCallback onReport;

  const RouteScreen({
    super.key,
    required this.phase,
    required this.postReroute,
    required this.riskUpgraded,
    required this.isOffline,
    required this.onPhaseChange,
    required this.onRerouted,
    required this.onNotNow,
    required this.onReport,
  });

  @override
  ConsumerState<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends ConsumerState<RouteScreen> {
  bool _expanded = false;
  bool _compareOpen = false;
  double _progress = 0;
  Timer? _calcTimer;
  Timer? _autoTrigger;

  @override
  void initState() {
    super.initState();
    _startAutoTrigger();
  }

  @override
  void didUpdateWidget(RouteScreen old) {
    super.didUpdateWidget(old);
    if (widget.phase != old.phase) {
      if (widget.phase == TripPhase.calculating) _startCalc();
    }
    if (widget.phase == TripPhase.active && old.phase != TripPhase.active) {
      _startAutoTrigger();
    }
  }

  void _startAutoTrigger() {
    _autoTrigger?.cancel();
    if (!widget.postReroute) {
      _autoTrigger = Timer(const Duration(seconds: 8), () {
        if (mounted && widget.phase == TripPhase.active) {
          widget.onPhaseChange(TripPhase.interrupt);
        }
      });
    }
  }

  void _startCalc() {
    _progress = 0;
    _calcTimer?.cancel();
    const step = Duration(milliseconds: 50);
    _calcTimer = Timer.periodic(step, (t) {
      setState(() {
        // Animate to 90 %, then hold until the OSRM detour search settles.
        _progress = (_progress + (50 / 1500) * 100)
            .clamp(0, _detourSettled() ? 100 : 90);
        if (_progress >= 100) {
          _progress = 100;
          t.cancel();
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              widget.onPhaseChange(TripPhase.rerouted);
            }
          });
        }
      });
    });
  }

  /// Route plan + detour: live from OSRM, or the baked snapshot when offline
  /// (and while the live request is in flight / if it fails).
  ({TripRoutePlan? plan, TripDetourPlan? detour, bool settled}) _routing() {
    if (widget.isOffline) {
      return (
        plan: TripSnapshots.fieldPlan(),
        detour: TripSnapshots.fieldDetour(),
        settled: true,
      );
    }
    final plan = ref.watch(fieldTripPlanProvider);
    final detour = ref.watch(fieldTripDetourProvider);
    return (
      plan: plan.valueOrNull ?? TripSnapshots.fieldPlan(),
      detour: detour.valueOrNull ??
          (detour.hasError ? TripSnapshots.fieldDetour() : null),
      settled: detour.hasValue || detour.hasError,
    );
  }

  bool _detourSettled() {
    if (widget.isOffline) return true;
    final d = ref.read(fieldTripDetourProvider);
    return d.hasValue || d.hasError;
  }

  @override
  void dispose() {
    _calcTimer?.cancel();
    _autoTrigger?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.phase;
    final rerouted = widget.postReroute;
    final risky = phase == TripPhase.interrupt ||
        phase == TripPhase.calculating;
    final routing = _routing();
    final copy = TripCopy(
      plan: routing.plan,
      detour: routing.detour,
      detourSettled: routing.settled,
    );

    return Column(
      children: [
        // ── Map area ────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              // Live map — includes recenter / terrain controls
              // (hidden after reroute, where the legend takes over).
              Positioned.fill(
                child: TripRouteMap(
                  phase: phase,
                  postReroute: rerouted,
                  riskUpgraded: widget.riskUpgraded,
                  isOffline: widget.isOffline,
                  plan: routing.plan,
                  detour: routing.detour,
                ),
              ),

              // Map legend (shown after reroute)
              if (phase == TripPhase.rerouted)
                const Positioned(
                  top: 12,
                  left: 12,
                  child: MapLegend(),
                ),

              // Critical alert card (interrupt phase)
              if (phase == TripPhase.interrupt)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _AlertCard(
                    copy: copy,
                    onNotNow: widget.onNotNow,
                    onViewSafer: () =>
                        widget.onPhaseChange(TripPhase.calculating),
                  ),
                ),
            ],
          ),
        ),

        // ── Bottom sheet ─────────────────────────────────────────
        _buildSheet(phase, rerouted, risky, copy),

        // Compare modal
        if (_compareOpen)
          _CompareModal(
            copy: copy,
            onClose: () => setState(() => _compareOpen = false),
          ),
      ],
    );
  }

  Widget _buildSheet(TripPhase phase, bool rerouted, bool risky, TripCopy copy) {
    if (phase == TripPhase.rerouted) {
      return _ReroutedSheet(
        copy: copy,
        onHold: widget.onNotNow,
        expanded: _expanded,
        onToggle: () => setState(() => _expanded = !_expanded),
        onCompare: () => setState(() => _compareOpen = true),
        onFollowNew: widget.onRerouted,
      );
    }
    if (risky) {
      return _CalculatingSheet(
        copy: copy,
        progress: _progress,
        expanded: _expanded,
        onToggle: () => setState(() => _expanded = !_expanded),
      );
    }
    return _ActiveSheet(
      copy: copy,
      rerouted: rerouted,
        riskUpgraded: widget.riskUpgraded,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      onReport: widget.onReport,
    );
  }
}

// ── Alert card (interrupt phase overlay) ─────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final TripCopy copy;
  final VoidCallback onNotNow;
  final VoidCallback onViewSafer;
  const _AlertCard({
    required this.copy,
    required this.onNotNow,
    required this.onViewSafer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.signalRed700),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Red header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.signalRed700,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_outlined,
                    size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Critical risk alert',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
                Text('now',
                    style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withOpacity(0.85))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.hazardTitle,
                  style: AppTextStyles.sectionHeading.copyWith(
                      fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  copy.hazardDetail,
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TripOutlineButton(
                        label: 'Not now',
                        onTap: onNotNow,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TripSolidButton(
                        label: 'View safer route',
                        color: AppColors.signalRed700,
                        onTap: onViewSafer,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active sheet ──────────────────────────────────────────────────────────────

class _ActiveSheet extends StatelessWidget {
  final TripCopy copy;
  final bool rerouted;
  final bool riskUpgraded;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onReport;
  const _ActiveSheet({
    required this.copy,
    required this.rerouted,
    required this.riskUpgraded,
    required this.expanded,
    required this.onToggle,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (_) {
            final turn = rerouted ? copy.followingTurn : copy.nextTurn;
            return NextTurnRow(
              km: turn.km,
              mainDirection: turn.main,
              subText: turn.sub,
              turnRight: turn.right,
            );
          }),
          const TripDivider(),
          StatPair(
            left: StatCol(
              label: 'ETA range',
              value: rerouted ? copy.followingEta : copy.eta,
            ),
            right: StatCol(
              label: 'Remaining',
              value: rerouted ? copy.followingRemaining : copy.remaining,
            ),
          ),
          const SizedBox(height: 12),
          if (!rerouted)
            TripBanner(
              tone: riskUpgraded
                  ? TripBannerTone.critical
                  : TripBannerTone.caution,
              label: riskUpgraded ? 'High risk' : 'Caution',
              text: riskUpgraded ? copy.hazardBanner : copy.cautionBanner,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TripOutlineButton(
                  label: 'Route detail',
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TripSolidButton(
                  label: 'Report condition',
                  onTap: onReport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Calculating sheet ─────────────────────────────────────────────────────────

class _CalculatingSheet extends StatelessWidget {
  final TripCopy copy;
  final double progress;
  final bool expanded;
  final VoidCallback onToggle;
  const _CalculatingSheet({
    required this.copy,
    required this.progress,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.signalRed700.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: AppColors.signalRed700.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_outlined,
                    size: 20, color: AppColors.signalRed700),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF3A2725)),
                      children: [
                        const TextSpan(
                          text: 'High risk ahead',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.signalRed700,
                          ),
                        ),
                        TextSpan(
                            text: ' · ${copy.hazardSpan} flagged on current route'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.navy900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  copy.detourSettled
                      ? 'Alternate route ready'
                      : 'Searching road network (OSRM)…',
                  style: AppTextStyles.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: const Color(0xFFE6E7E2),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.navy900),
              minHeight: 6,
            ),
          ),
          const TripDivider(),
          StatPair(
            left: StatCol(
              label: 'ETA range — on hold',
              value: copy.eta,
              strike: true,
            ),
            right: StatCol(
              label: 'Candidate route',
              value: copy.candidate,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rerouted sheet ────────────────────────────────────────────────────────────

class _ReroutedSheet extends StatelessWidget {
  final TripCopy copy;
  final VoidCallback onHold;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onCompare;
  final VoidCallback onFollowNew;
  const _ReroutedSheet({
    required this.copy,
    required this.onHold,
    required this.expanded,
    required this.onToggle,
    required this.onCompare,
    required this.onFollowNew,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = copy.noDetour;
    final tone = blocked ? AppColors.saffron600 : AppColors.deepGreen700;
    final turn = copy.detourTurn;
    return _Sheet(
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tone.withValues(alpha: 0.4)),
                ),
                child: Icon(
                    blocked ? Icons.pan_tool_outlined : Icons.check_circle_outline,
                    size: 20,
                    color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.reroutedTitle,
                      style: AppTextStyles.sectionHeading.copyWith(fontSize: 19),
                    ),
                    const SizedBox(height: 4),
                    Text(copy.reroutedBody, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const TripDivider(),
          StatPair(
            left: StatCol(
              label: blocked ? 'ETA range — on hold' : 'New ETA range',
              value: copy.rerouteEta,
              note: copy.rerouteDelay,
              noteTone: StatNoteTone.saffron,
            ),
            right: StatCol(
              label: 'Risk exposure',
              value: blocked ? 'High · hold' : copy.rerouteRisk,
              note: 'was High · 1 blocked',
              noteTone: StatNoteTone.muted,
            ),
          ),
          if (turn != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F1EC),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(turn.right ? Icons.turn_right_outlined : Icons.turn_left_outlined,
                      size: 20, color: AppColors.slate500),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTextStyles.bodySmallMedium,
                        children: [
                          TextSpan(
                            text: 'Next turn · ${turn.km}\n',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: '${turn.main}, ${turn.sub}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!blocked) ...[
                Expanded(
                  child: TripOutlineButton(label: 'Compare', onTap: onCompare),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: TripSolidButton(
                  label: blocked ? 'Hold at safe point' : 'Follow new route',
                  onTap: blocked ? onHold : onFollowNew,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Generic sheet wrapper ─────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  const _Sheet({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxHeight: expanded
            ? MediaQuery.of(context).size.height * 0.78
            : double.infinity,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SingleChildScrollView(
        physics: expanded
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            SheetHandle(onTap: onToggle),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Compare modal ─────────────────────────────────────────────────────────────

class _CompareModal extends StatelessWidget {
  final TripCopy copy;
  final VoidCallback onClose;
  const _CompareModal({required this.copy, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withOpacity(0.40),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SheetHandle(onTap: null),
                    const SizedBox(height: 4),
                    Text('Compare routes',
                        style: AppTextStyles.pageHeading),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _CompareCol(
                            title: 'Original',
                            titleColor: AppColors.signalRed700,
                            eta: copy.eta,
                            risk: 'High · 1 blocked',
                            note: '${copy.hazardSpan} landslide risk',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CompareCol(
                            title: 'Rerouted',
                            titleColor: AppColors.deepGreen700,
                            eta: copy.rerouteEta,
                            risk: copy.rerouteRisk,
                            note: '${copy.rerouteDelay} · via ${copy.via}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onClose,
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompareCol extends StatelessWidget {
  final String title;
  final Color titleColor;
  final String eta, risk, note;
  const _CompareCol({
    required this.title,
    required this.titleColor,
    required this.eta,
    required this.risk,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.cardTitle
                  .copyWith(color: titleColor)),
          const SizedBox(height: 10),
          Text('ETA', style: AppTextStyles.caption),
          Text(eta, style: AppTextStyles.statValue.copyWith(fontSize: 17)),
          const SizedBox(height: 8),
          Text('Risk exposure', style: AppTextStyles.caption),
          Text(risk,
              style: AppTextStyles.cardTitle
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(note, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
