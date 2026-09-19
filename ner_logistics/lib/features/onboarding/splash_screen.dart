import 'package:flutter/material.dart';
import '../../shared/ashoka_chakra.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// SplashScreen — tricolor gradient background, spinning AshokaChakra,
/// platform identity lockup, and two CTAs.
/// Matches React SplashScreen exactly.
class SplashScreen extends StatelessWidget {
  final VoidCallback onLogIn;
  final VoidCallback onCreateAccount;

  const SplashScreen({
    super.key,
    required this.onLogIn,
    required this.onCreateAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.08, 0.22, 0.37, 0.52, 0.66, 0.80, 0.92, 1.0],
            colors: AppColors.splashGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Status bar row ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Text(
                      '09:41',
                      style: AppTextStyles.statusBarTime.copyWith(
                        color: AppColors.navy900,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.signal_cellular_alt,
                        size: 18, color: AppColors.navy900.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Icon(Icons.wifi,
                        size: 18, color: AppColors.navy900.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Icon(Icons.battery_full,
                        size: 18, color: AppColors.navy900.withOpacity(0.7)),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // ── Spinning Ashoka Chakra ─────────────────────────
              SpinningAshokaChakra(
                size: 120,
                color: AppColors.navy900,
                duration: const Duration(seconds: 18),
              ),

              const SizedBox(height: 28),

              // ── Identity lockup ───────────────────────────────
              Column(
                children: [
                  Text(
                    'Janrakshak AI',
                    style: AppTextStyles.heroHeading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'MDoNER · SIH26002',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.navy900.withOpacity(0.55),
                      fontFamily: 'NotoSans',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.navy900.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'North Eastern Region · Official Use Only',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.navy900.withOpacity(0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 3),

              // ── CTA buttons ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Log in — primary
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: onLogIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy900,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Log in',
                          style: AppTextStyles.button,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Create account — outlined
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: onCreateAccount,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy900,
                          side: BorderSide(
                            color: AppColors.navy900.withOpacity(0.45),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Create account',
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.navy900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Legal footer ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'For official use only. Activity on this system is monitored and logged.',
                  style: AppTextStyles.disclaimer,
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
