import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bgDark = Color(0xFF0F1E33); // app shell / nav / map base
  static const bgRaised = Color(0xFF1A2D48); // fields and chips on the dark shell
  static const bgLight = Color(0xFFE8E3D3); // cards / panels
  static const accent = Color(0xFFD89A2E); // active state, primary CTAs, badges
  static const statusOk = Color(0xFF1F7A5C);
  static const statusCritical = Color(0xFFB23B2E);
  static const statusHigh = Color(0xFFD8752E);
  static const statusModerate = Color(0xFFD9A63E);
  static const statusUnknown = Color(0xFF8A94A3);
  static const textOnDark = Colors.white;
  static const textOnLight = Color(0xFF1B2A3D);
}

class AppTheme {
  static const mutedOnDark = Color(0xB3FFFFFF);

  static TextTheme _text(Color color) {
    final body = GoogleFonts.publicSansTextTheme().apply(bodyColor: color, displayColor: color);
    TextStyle head(TextStyle? s, double size) => GoogleFonts.barlowCondensed(
        textStyle: s, fontSize: size, fontWeight: FontWeight.w700, color: color, height: 1.1);
    return body.copyWith(
      displayLarge: head(body.displayLarge, 44),
      displayMedium: head(body.displayMedium, 36),
      headlineLarge: head(body.headlineLarge, 32),
      headlineMedium: head(body.headlineMedium, 28),
      headlineSmall: head(body.headlineSmall, 24),
      titleLarge: head(body.titleLarge, 22),
      // Eyebrow style ("ACTIVE REGION"); callers upper-case via the Eyebrow widget.
      labelSmall: body.labelSmall!.copyWith(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: AppColors.accent),
    );
  }

  static final ThemeData dark = () {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.bgDark,
      secondary: AppColors.accent,
      surface: AppColors.bgDark,
      onSurface: AppColors.textOnDark,
      surfaceContainerHighest: AppColors.bgRaised,
      error: AppColors.statusCritical,
    );
    final text = _text(AppColors.textOnDark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: AppColors.bgDark,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDark,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bgDark,
        indicatorColor: AppColors.accent,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.bgDark : AppColors.textOnDark)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? AppColors.accent : AppTheme.mutedOnDark)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgRaised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent)),
        labelStyle: const TextStyle(color: mutedOnDark),
        helperStyle: const TextStyle(color: mutedOnDark),
        counterStyle: const TextStyle(color: mutedOnDark),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgRaised,
        selectedColor: AppColors.accent,
        secondarySelectedColor: AppColors.accent,
        checkmarkColor: AppColors.bgDark,
        labelStyle: text.labelLarge,
        secondaryLabelStyle: text.labelLarge!.copyWith(color: AppColors.bgDark),
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.accent : AppColors.bgRaised),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.bgDark : AppColors.textOnDark),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.bgDark, foregroundColor: AppColors.accent),
      dividerTheme: const DividerThemeData(color: AppColors.bgRaised),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }();

  /// Same theme with dark-on-light text, for content sitting on an `AppColors.bgLight` panel.
  static ThemeData onLight(ThemeData base) {
    final text = base.textTheme.apply(bodyColor: AppColors.textOnLight, displayColor: AppColors.textOnLight);
    return base.copyWith(
      textTheme: text.copyWith(labelSmall: text.labelSmall!.copyWith(color: AppColors.textOnLight.withAlpha(180))),
      iconTheme: const IconThemeData(color: AppColors.textOnLight),
      dividerColor: AppColors.textOnLight.withAlpha(30),
      listTileTheme: const ListTileThemeData(textColor: AppColors.textOnLight, iconColor: AppColors.textOnLight),
    );
  }
}
