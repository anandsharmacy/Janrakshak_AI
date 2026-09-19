import 'package:flutter/material.dart';
import '../../../mock_data/mock_routes.dart';
import '../../ml/presentation/ml_widgets.dart';
import '../../../mock_data/models.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../../../theme/colors.dart';
import '../../../theme/text_styles.dart';

class RouteStatusScreen extends StatefulWidget {
  const RouteStatusScreen({super.key});

  @override
  State<RouteStatusScreen> createState() => _RouteStatusScreenState();
}

class _RouteStatusScreenState extends State<RouteStatusScreen> {
  String? _selectedId;
  bool _showToast = false;

  RouteInfo? get _selectedRoute =>
      _selectedId == null
          ? null
          : mockRoutes.where((r) => r.id == _selectedId).firstOrNull;

  Color _scoreColor(int score) {
    if (score >= 80) return AppColors.deepGreen700;
    if (score >= 50) return AppColors.saffron600;
    return AppColors.signalRed700;
  }

  Color _scoreLabelColor(int score) {
    if (score >= 80) return AppColors.deepGreen700;
    if (score >= 50) return AppColors.saffronDark;
    return AppColors.signalRed700;
  }

  void _showIncidentToast() {
    setState(() => _showToast = true);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _selectedRoute == null
            ? _buildListView()
            : RouteDetailView(
                route: _selectedRoute!,
                onBack: () => setState(() => _selectedId = null),
                onViewIncidents: _showIncidentToast,
              ),
        if (_showToast)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.navy900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.white.withOpacity(0.8)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Incident history is available when connected to network.',
                        style: AppTextStyles.caption.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.slate500.withOpacity(0.10), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '4 routes monitored · Ri Bhoi district',
                  style: AppTextStyles.tabLabel.copyWith(
                    color: AppColors.slate500.withOpacity(0.60),
                    fontFamily: 'PublicSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Road disruption risk (model)', style: AppTextStyles.bodySmallMedium),
                const SizedBox(height: 8),
                const MlRoutesBoard(),
                const SizedBox(height: 16),
                Text('Reported route status (demo data)', style: AppTextStyles.bodySmallMedium),
                const SizedBox(height: 8),
                ...mockRoutes.asMap().entries.map((entry) {
                  final route = entry.value;
                  final isLast = entry.key == mockRoutes.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                    child: _RouteCard(
                      route: route,
                      onTap: () => setState(() => _selectedId = route.id),
                      scoreColor: _scoreColor(route.score),
                      scoreLabelColor: _scoreLabelColor(route.score),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RouteInfo route;
  final VoidCallback onTap;
  final Color scoreColor;
  final Color scoreLabelColor;

  const _RouteCard({
    required this.route,
    required this.onTap,
    required this.scoreColor,
    required this.scoreLabelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: AppColors.navy900.withOpacity(0.06),
        highlightColor: AppColors.navy900.withOpacity(0.03),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.slate500.withOpacity(0.20), width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.navy900,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      route.id,
                      style: const TextStyle(
                        fontFamily: 'PublicSans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        route.name,
                        style: const TextStyle(
                          fontFamily: 'PublicSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RiskBadge(level: route.risk),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: route.score / 100,
                        backgroundColor: AppColors.slate500.withOpacity(0.10),
                        valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                        minHeight: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${route.score}/100',
                    style: TextStyle(
                      fontFamily: 'PublicSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scoreLabelColor,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                route.condition,
                style: const TextStyle(
                  fontFamily: 'NotoSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.slate500,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (route.incidentCount > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning, size: 13, color: AppColors.signalRed700),
                        const SizedBox(width: 4),
                        Text(
                          '${route.incidentCount} incident${route.incidentCount != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.signalRed700,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined, size: 13, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Text(
                        route.weather,
                        style: const TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.slate500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_outlined, size: 13, color: AppColors.slate500),
                      const SizedBox(width: 4),
                      Text(
                        route.updatedAt,
                        style: const TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.slate500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteDetailView extends StatelessWidget {
  final RouteInfo route;
  final VoidCallback onBack;
  final VoidCallback onViewIncidents;

  const RouteDetailView({
    super.key,
    required this.route,
    required this.onBack,
    required this.onViewIncidents,
  });

  Color get _scoreColor {
    if (route.score >= 80) return AppColors.deepGreen700;
    if (route.score >= 50) return AppColors.saffron600;
    return AppColors.signalRed700;
  }

  Color get _scoreLabelColor {
    if (route.score >= 80) return AppColors.deepGreen700;
    if (route.score >= 50) return AppColors.saffronDark;
    return AppColors.signalRed700;
  }

  Color get _bannerBg {
    switch (route.risk) {
      case RiskLevel.clear:
        return AppColors.clearBg;
      case RiskLevel.caution:
        return AppColors.saffronBg;
      case RiskLevel.critical:
        return AppColors.criticalBg;
    }
  }

  Color get _bannerBorder {
    switch (route.risk) {
      case RiskLevel.clear:
        return AppColors.deepGreen700.withOpacity(0.30);
      case RiskLevel.caution:
        return AppColors.saffron600.withOpacity(0.30);
      case RiskLevel.critical:
        return AppColors.signalRed700.withOpacity(0.30);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(6),
            splashColor: AppColors.navy900.withOpacity(0.06),
            highlightColor: AppColors.navy900.withOpacity(0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.chevron_left, size: 20, color: AppColors.navy900),
                  const SizedBox(width: 2),
                  Text(
                    'Route Status',
                    style: const TextStyle(
                      fontFamily: 'PublicSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy900,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            route.name,
            style: const TextStyle(
              fontFamily: 'PublicSans',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.navy900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Updated ${route.updatedAt}',
            style: const TextStyle(
              fontFamily: 'NotoSans',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.slate500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${route.score}',
                style: TextStyle(
                  fontFamily: 'PublicSans',
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: _scoreLabelColor,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/100',
                  style: const TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slate500,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACCESSIBILITY',
                      style: const TextStyle(
                        fontFamily: 'PublicSans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.88,
                        color: AppColors.slate500,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: 1,
                height: 28,
                color: AppColors.slate500.withOpacity(0.15),
              ),
              const SizedBox(width: 12),
              RiskBadge(level: route.risk),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: route.score / 100,
              backgroundColor: AppColors.slate500.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(_scoreColor),
              minHeight: 2,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.slate500.withOpacity(0.15)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Row(
                  children: [
                    _buildDetailCell('Flood Risk', route.detail.floodRisk, false, false),
                    Container(width: 1, height: 68, color: AppColors.slate500.withOpacity(0.15)),
                    _buildDetailCell('Landslide Risk', route.detail.landslideRisk, false, true),
                  ],
                ),
                Container(height: 1, width: double.infinity, color: AppColors.slate500.withOpacity(0.15)),
                Row(
                  children: [
                    _buildDetailCell('Blockage', route.detail.blockage, false, false),
                    Container(width: 1, height: 68, color: AppColors.slate500.withOpacity(0.15)),
                    _buildDetailCell('Condition', route.condition, false, true),
                  ],
                ),
                Container(height: 1, width: double.infinity, color: AppColors.slate500.withOpacity(0.15)),
                Row(
                  children: [
                    _buildDetailCell('Weather', route.weather, true, false),
                    Container(width: 1, height: 68, color: AppColors.slate500.withOpacity(0.15)),
                    _buildDetailCell('Incidents', '${route.incidentCount} active', true, true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.slate500.withOpacity(0.15)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time_outlined, size: 16, color: AppColors.slate500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route.detail.history,
                    style: const TextStyle(
                      fontFamily: 'NotoSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.slate500,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bannerBg,
              border: Border.all(color: _bannerBorder, width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECOMMENDED ACTION',
                  style: TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.88,
                    color: AppColors.slate500.withOpacity(0.65),
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  route.detail.recommendedAction,
                  style: TextStyle(
                    fontFamily: 'PublicSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _scoreLabelColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onViewIncidents,
              icon: const Icon(Icons.history, size: 16),
              label: const Text('All incidents on this route'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                textStyle: const TextStyle(
                  fontFamily: 'PublicSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                foregroundColor: AppColors.navy900,
                side: BorderSide(color: AppColors.slate500.withOpacity(0.25)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDetailCell(String label, String value, bool isLastRow, bool isLastCol) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'PublicSans',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppColors.slate500.withOpacity(0.60),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.navy900,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
