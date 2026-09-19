import 'package:flutter/material.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'card_surface.dart';
import 'risk_badge.dart';

/// RouteCard — route list tile used in RouteStatusScreen.
/// Shows route ID badge, name, score bar, condition text, and meta row.
class RouteCard extends StatelessWidget {
  final RouteInfo route;
  final VoidCallback onTap;

  const RouteCard({super.key, required this.route, required this.onTap});

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.deepGreen700;
    if (score >= 50) return AppColors.saffron600;
    return AppColors.signalRed700;
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(route.score);

    return CardSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: ID badge + name + risk badge ───────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.navy900,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        route.id,
                        style: AppTextStyles.eyebrowMd.copyWith(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        route.name,
                        style: AppTextStyles.cardTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RiskBadge(level: route.risk),
            ],
          ),

          // ── Score bar ───────────────────────────────────────────
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: route.score / 100,
                    backgroundColor: AppColors.slate500.withOpacity(0.1),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(scoreColor),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${route.score}/100',
                style: AppTextStyles.captionSemibold.copyWith(
                  color: scoreColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          // ── Condition ───────────────────────────────────────────
          const SizedBox(height: 8),
          Text(route.condition, style: AppTextStyles.bodySmall),

          // ── Meta row ────────────────────────────────────────────
          const SizedBox(height: 8),
          Row(
            children: [
              if (route.incidentCount > 0) ...[
                Icon(Icons.warning_amber_outlined,
                    size: 13, color: AppColors.signalRed700),
                const SizedBox(width: 4),
                Text(
                  '${route.incidentCount} incident${route.incidentCount != 1 ? "s" : ""}',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.signalRed700),
                ),
                const SizedBox(width: 12),
              ],
              Icon(Icons.location_on_outlined,
                  size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(route.weather,
                    style: AppTextStyles.caption,
                    overflow: TextOverflow.ellipsis),
              ),
              Icon(Icons.access_time_outlined,
                  size: 13, color: AppColors.slate500),
              const SizedBox(width: 4),
              Text(route.updatedAt, style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }
}
