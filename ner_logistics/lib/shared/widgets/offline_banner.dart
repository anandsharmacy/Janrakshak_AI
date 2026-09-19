import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// OfflineBanner — persistent top strip shown when connectivity drops.
/// Never blocks interaction — informational only.
class OfflineBanner extends StatelessWidget {
  final bool isOffline;

  const OfflineBanner({super.key, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: isOffline ? 32 : 0,
      color: AppColors.saffron600.withOpacity(0.15),
      child: isOffline
          ? Row(
              children: [
                const SizedBox(width: 16),
                Icon(
                  Icons.wifi_off_outlined,
                  size: 14,
                  color: AppColors.saffronDark,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "You're offline. Reports will send when you're back online.",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.saffronDark,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
