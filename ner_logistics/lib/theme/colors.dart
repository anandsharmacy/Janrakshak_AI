import 'package:flutter/material.dart';

/// NER Logistics Platform — Design Tokens
/// Source: frontend-requirements-design-system.md §4 + React source audit
/// Rule: color is NEVER used alone for risk — always pair with icon + text label.

class AppColors {
  AppColors._();

  // ── Primary palette ──────────────────────────────────────────────
  /// Headers, primary buttons, active nav, drawer background
  static const Color navy900 = Color(0xFF0E2A47);

  /// Pressed / hover state on navy surfaces
  static const Color navy700 = Color(0xFF1B3F63);

  /// Subtle navy tints used for backgrounds
  static const Color navyTint = Color(0x0F0E2A47); // navy @ 6%

  // ── Background ───────────────────────────────────────────────────
  /// Base screen background — cool off-white, not warm cream
  static const Color paper = Color(0xFFF5F5F1);

  // ── Risk / semantic ──────────────────────────────────────────────
  /// Caution / medium-risk / warning banners — amber-orange
  static const Color saffron600 = Color(0xFFD97A1F);

  /// Caution label text on light surfaces
  static const Color saffronDark = Color(0xFF7A4310);

  /// Caution background tint
  static const Color saffronBg = Color(0x1AD97A1F); // saffron @ 10%

  /// High-risk / blocked / critical alert — true red. NEVER decorative.
  static const Color signalRed700 = Color(0xFFB3261E);

  /// Critical background tint
  static const Color criticalBg = Color(0x0DB3261E); // red @ 5%

  /// Clear / low-risk / success / synced — deep green
  static const Color deepGreen700 = Color(0xFF1E6B45);

  /// Clear background tint
  static const Color clearBg = Color(0x1A1E6B45); // green @ 10%

  // ── Body / secondary ─────────────────────────────────────────────
  /// Body text on light surfaces, secondary labels
  static const Color slate500 = Color(0xFF5B6472);

  // ── Role-identity accent ─────────────────────────────────────────
  /// FO / DO / CO avatar badge, active nav indicator.
  /// NEVER used for risk semantics.
  static const Color gold = Color(0xFFD9A441);

  // ── Surface / border ─────────────────────────────────────────────
  /// 1 px hairline card borders and dividers
  static const Color hairline = Color(0x33C4C8CD); // ~20% opacity slate

  /// White card surface
  static const Color cardSurface = Color(0xFFFFFFFF);

  // ── Status indicators ────────────────────────────────────────────
  /// "System Online" dot
  static const Color systemOnline = Color(0xFF5FD39A);

  // ── Splash gradient stops ────────────────────────────────────────
  static const List<Color> splashGradient = [
    Color(0xFFB8762A),
    Color(0xFFC07A2E),
    Color(0xFFD4A870),
    Color(0xFFEEE5D5),
    Color(0xFFEDE3D2),
    Color(0xFFC8D8C0),
    Color(0xFF4A8860),
    Color(0xFF2C5C40),
    Color(0xFF1E4832),
  ];

  // ── Login background gradient stops ──────────────────────────────
  static const List<Color> loginGradient = [
    Color(0xFFF9ECD6),
    Color(0xFFF7EDE0),
    Color(0xFFF5F0E9),
    Color(0xFFF4F1EB),
    Color(0xFFEDF4F0),
    Color(0xFFE8F2EC),
    Color(0xFFE3EFE9),
  ];

  // ── Semantic aliases (use these in widgets) ───────────────────────
  static const Color primary = navy900;
  static const Color primaryPressed = navy700;
  static const Color background = paper;
  static const Color ink = slate500;
  static const Color critical = signalRed700;
  static const Color caution = saffron600;
  static const Color clear = deepGreen700;
  static const Color surface = cardSurface;
}
