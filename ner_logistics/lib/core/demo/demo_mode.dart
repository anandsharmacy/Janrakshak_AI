import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide switch for the built-in sample data (incidents, routes, fleet,
/// tasks, deliveries, trips…). On by default; the choice is kept on-device.
///
/// The `mock_data/` sources read [DemoMode.enabled] and return empty lists
/// while it is off, so they can be used from anywhere without a `ref`.
/// Flip it through [demoModeProvider] so the UI rebuilds.
class DemoMode {
  DemoMode._();

  static const _prefsKey = 'demo_data_enabled';

  static bool enabled = true;

  /// Reads the saved choice. Call once before `runApp`.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      // Storage unavailable: keep the default for this run.
    }
  }

  static Future<void> _save(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // The choice still applies for this run.
    }
  }
}

/// [data] while demo mode is on, otherwise an empty list.
List<T> demoOnly<T>(List<T> data) => DemoMode.enabled ? data : <T>[];

class DemoModeNotifier extends StateNotifier<bool> {
  DemoModeNotifier() : super(DemoMode.enabled);

  void set(bool value) {
    if (value == state) return;
    DemoMode.enabled = value;
    state = value;
    DemoMode._save(value);
  }
}

final demoModeProvider =
    StateNotifierProvider<DemoModeNotifier, bool>((ref) => DemoModeNotifier());
