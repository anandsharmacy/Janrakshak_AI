import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';

/// Trip screen reusable widgets:
///   - NextTurnRow    — large turn-direction box with km + street name
///   - StatPair       — two stat columns separated by a vertical hairline
///   - TripBanner     — caution / critical inline banner inside the sheet
///   - TripDivider    — full-width hairline divider with vertical margin
///   - SolidButton    — navy filled CTA button
///   - OutlineButton  — navy outlined CTA button
///   - SheetHandle    — drag pill at top of every bottom sheet

// ── NextTurnRow ───────────────────────────────────────────────────────────────

class NextTurnRow extends StatelessWidget {
  final String km;
  final String mainDirection;
  final String subText;
  final bool turnRight;

  const NextTurnRow({
    super.key,
    required this.km,
    required this.mainDirection,
    required this.subText,
    this.turnRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Turn icon box
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(
            turnRight
                ? Icons.turn_right_outlined
                : Icons.turn_left_outlined,
            size: 30,
            color: AppColors.navy900,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next turn · $km',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  mainDirection,
                  style: AppTextStyles.statLarge.copyWith(fontSize: 21),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(subText, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── StatPair ─────────────────────────────────────────────────────────────────

class StatPair extends StatelessWidget {
  final StatCol left;
  final StatCol right;

  const StatPair({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(child: _StatColView(col: left)),
          Container(width: 1, color: AppColors.hairline),
          const SizedBox(width: 16),
          Expanded(child: _StatColView(col: right)),
        ],
      ),
    );
  }
}

class StatCol {
  final String label;
  final String value;
  final bool strike;
  final String? note;
  final StatNoteTone noteTone;

  const StatCol({
    required this.label,
    required this.value,
    this.strike = false,
    this.note,
    this.noteTone = StatNoteTone.muted,
  });
}

enum StatNoteTone { saffron, muted }

class _StatColView extends StatelessWidget {
  final StatCol col;
  const _StatColView({required this.col});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(col.label, style: AppTextStyles.bodySmall),
        const SizedBox(height: 2),
        Text(
          col.value,
          style: AppTextStyles.statValue.copyWith(
            decoration:
                col.strike ? TextDecoration.lineThrough : null,
            color: col.strike ? AppColors.slate500 : AppColors.navy900,
          ),
        ),
        if (col.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              col.note!,
              style: AppTextStyles.bodySmall.copyWith(
                color: col.noteTone == StatNoteTone.saffron
                    ? AppColors.saffron600
                    : AppColors.slate500.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ── TripBanner ────────────────────────────────────────────────────────────────

enum TripBannerTone { caution, critical }

class TripBanner extends StatelessWidget {
  final TripBannerTone tone;
  final String label;
  final String text;

  const TripBanner({
    super.key,
    required this.tone,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isCritical = tone == TripBannerTone.critical;
    final borderColor = isCritical
        ? AppColors.signalRed700.withOpacity(0.4)
        : AppColors.saffron600.withOpacity(0.4);
    final bgColor = isCritical
        ? AppColors.signalRed700.withOpacity(0.05)
        : AppColors.saffron600.withOpacity(0.1);
    final iconColor =
        isCritical ? AppColors.signalRed700 : AppColors.saffron600;
    final labelColor =
        isCritical ? AppColors.signalRed700 : AppColors.saffronDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_outlined, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTextStyles.bodySmallMedium.copyWith(
                    color: AppColors.navy900),
                children: [
                  TextSpan(
                    text: '$label ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    ),
                  ),
                  TextSpan(text: '· $text'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── TripDivider ───────────────────────────────────────────────────────────────

class TripDivider extends StatelessWidget {
  const TripDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 14),
      color: AppColors.hairline,
    );
  }
}

// ── SolidButton ───────────────────────────────────────────────────────────────

class TripSolidButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const TripSolidButton({
    super.key,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? AppColors.navy900,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        child: Text(label,
            style:
                AppTextStyles.button.copyWith(color: Colors.white)),
      ),
    );
  }
}

// ── OutlineButton ─────────────────────────────────────────────────────────────

class TripOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const TripOutlineButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy900,
          side: const BorderSide(color: AppColors.navy900),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label, style: AppTextStyles.button),
      ),
    );
  }
}

// ── SheetHandle ───────────────────────────────────────────────────────────────

class SheetHandle extends StatelessWidget {
  final VoidCallback? onTap;

  const SheetHandle({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFC4C8CD),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
