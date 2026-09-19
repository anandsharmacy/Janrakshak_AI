import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import 'card_surface.dart';

/// AiCard — labeled AI-generated estimate / prediction card.
/// Every AI output is clearly labeled with kind, confidence, and disclaimer.
///
/// [demo] marks scripted prototype content: it is badged DEMO and says it is
/// not model output, so it can't be mistaken for live ML (SRS ML-011). Live
/// model output uses the ML widgets in `features/ml/presentation`.
class AiCard extends StatelessWidget {
  final String kind;
  final int? confidence;
  final String title;
  final Widget body;
  final bool demo;

  const AiCard({
    super.key,
    required this.kind,
    this.confidence,
    required this.title,
    required this.body,
    this.demo = false,
  });

  @override
  Widget build(BuildContext context) {
    return CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header strip ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.navy900.withOpacity(0.04),
              border: Border(
                bottom: BorderSide(color: AppColors.hairline),
              ),
            ),
            child: Row(
              children: [
                // AI badge
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.navy900,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    demo ? 'D' : 'AI',
                    style: AppTextStyles.eyebrow.copyWith(
                      color: Colors.white,
                      fontSize: 8,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kind.toUpperCase(),
                    style: AppTextStyles.eyebrow.copyWith(
                      color: AppColors.navy900,
                    ),
                  ),
                ),
                if (confidence != null && !demo)
                  Text(
                    '$confidence% confidence',
                    style: AppTextStyles.captionSemibold,
                  ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.cardTitle),
                const SizedBox(height: 6),
                body,
                const SizedBox(height: 10),
                Text(
                  demo
                      ? 'Illustrative demo content — not model output.'
                      : 'AI-generated estimate — verify before acting.',
                  style: AppTextStyles.disclaimer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Convenience text body for AiCard
class AiCardText extends StatelessWidget {
  final String text;
  const AiCardText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.bodySmall,
    );
  }
}
