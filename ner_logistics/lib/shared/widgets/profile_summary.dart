import 'package:flutter/material.dart';
import '../../mock_data/models.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// ProfileSummary — officer identity block used at the top of every drawer.
/// Shows role avatar, name, officer ID, role badge, area, and online status.
class ProfileSummary extends StatelessWidget {
  final Officer officer;
  final bool showArea;

  const ProfileSummary({
    super.key,
    required this.officer,
    this.showArea = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  officer.initials,
                  style: AppTextStyles.eyebrowMd.copyWith(
                    color: AppColors.navy900,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      officer.roleLabel,
                      style: AppTextStyles.cardTitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Janrakshak AI Operations Portal',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showArea) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    officer.role == AppRole.control
                        ? 'Regional Control'
                        : 'Assigned Area',
                    style: AppTextStyles.eyebrow.copyWith(
                      color: Colors.white.withOpacity(0.45),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    officer.region,
                    style: AppTextStyles.bodySmallMedium.copyWith(
                      color: Colors.white,
                      fontFamily: 'PublicSans',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.systemOnline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'System Online',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.systemOnline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
