import 'package:flutter/material.dart';
import 'colors.dart';

/// NER Logistics Platform — Typography Scale
/// Public Sans  → UI chrome, headings, buttons, labels, KPI values
/// Noto Sans    → body text, descriptions, form fields, multilingual data
///
/// Minimum 14sp anywhere; minimum 16sp for field-officer-track body text.
/// Sentence case throughout — no all-caps in running text; only eyebrow labels.

class AppTextStyles {
  AppTextStyles._();

  // ── Font family constants ─────────────────────────────────────────
  static const String _public = 'PublicSans';
  static const String _noto = 'NotoSans';

  // ── Public Sans scale ─────────────────────────────────────────────

  /// Splash / onboarding hero heading — 26sp bold
  static const TextStyle heroHeading = TextStyle(
    fontFamily: _public,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.navy900,
    height: 1.2,
  );

  /// Screen title in header chrome — 20sp bold
  static const TextStyle screenTitle = TextStyle(
    fontFamily: _public,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.25,
  );

  /// Page / section heading — 22sp bold (e.g. "My Tasks")
  static const TextStyle pageHeading = TextStyle(
    fontFamily: _public,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.navy900,
    height: 1.25,
  );

  /// Card / sub-section heading — 18–20sp bold
  static const TextStyle sectionHeading = TextStyle(
    fontFamily: _public,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.navy900,
    height: 1.3,
  );

  /// Card title / list item primary — 15–16sp semibold
  static const TextStyle cardTitle = TextStyle(
    fontFamily: _public,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.navy900,
    height: 1.35,
  );

  /// Section title in body — 15sp bold (used by SectionTitle widget)
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: _public,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.navy900,
  );

  /// KPI large value — 26sp bold
  static const TextStyle kpiValue = TextStyle(
    fontFamily: _public,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  /// Stat value (ETA, score) — 20sp bold
  static const TextStyle statValue = TextStyle(
    fontFamily: _public,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.navy900,
    height: 1.1,
  );

  /// Large stat (route score, rerouted heading) — 22sp bold
  static const TextStyle statLarge = TextStyle(
    fontFamily: _public,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.navy900,
    height: 1.1,
  );

  /// Button label — 16sp bold
  static const TextStyle button = TextStyle(
    fontFamily: _public,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  /// Small button / secondary action — 14sp semibold
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: _public,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );

  /// Tab bar label — 13–14sp semibold
  static const TextStyle tabLabel = TextStyle(
    fontFamily: _public,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// Status chip / badge label — 12–13sp semibold
  static const TextStyle chipLabel = TextStyle(
    fontFamily: _public,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );

  /// Eyebrow / field label — 10–11sp bold UPPERCASE with letter-spacing
  static const TextStyle eyebrow = TextStyle(
    fontFamily: _public,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
    height: 1.0,
  );

  /// Eyebrow 11sp variant (slightly larger)
  static const TextStyle eyebrowMd = TextStyle(
    fontFamily: _public,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.88,
    height: 1.0,
  );

  /// Meta / timestamp / ID — 12sp regular
  static const TextStyle meta = TextStyle(
    fontFamily: _public,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.slate500,
  );

  /// Status bar time — 15sp bold
  static const TextStyle statusBarTime = TextStyle(
    fontFamily: _public,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: -0.3,
  );

  // ── Noto Sans scale ───────────────────────────────────────────────

  /// Body text — 15sp regular (field officer minimum)
  static const TextStyle body = TextStyle(
    fontFamily: _noto,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.slate500,
    height: 1.5,
  );

  /// Body medium — 15sp medium
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _noto,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.navy900,
    height: 1.5,
  );

  /// Body small — 14sp regular
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _noto,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.slate500,
    height: 1.45,
  );

  /// Body small medium — 14sp medium
  static const TextStyle bodySmallMedium = TextStyle(
    fontFamily: _noto,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.navy900,
    height: 1.45,
  );

  /// Caption / fine print — 12sp regular
  static const TextStyle caption = TextStyle(
    fontFamily: _noto,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.slate500,
    height: 1.4,
  );

  /// Caption semibold — 12sp semibold (district sub-headers)
  static const TextStyle captionSemibold = TextStyle(
    fontFamily: _noto,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.slate500,
  );

  /// Fine print / legal / disclaimer — 11sp regular italic
  static const TextStyle disclaimer = TextStyle(
    fontFamily: _noto,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.slate500,
    fontStyle: FontStyle.italic,
    height: 1.5,
  );

  /// Form field input text — 15sp regular
  static const TextStyle inputText = TextStyle(
    fontFamily: _noto,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.navy900,
  );

  /// Form field hint / placeholder — 15sp regular muted
  static const TextStyle inputHint = TextStyle(
    fontFamily: _noto,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: Color(0x4D0E2A47), // navy @ 30%
  );
}
