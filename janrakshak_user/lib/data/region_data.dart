import 'dart:convert';

import 'package:flutter/services.dart';

/// Single source for region / state / district / incident-type lookups.
/// `regionToStates` and `stateToDistricts` come from assets/region_data.json
/// (built once from the CSV by tool/build_region_data.py); call [load] before runApp.
class RegionData {
  static Map<String, List<String>> regionToStates = const {};
  static Map<String, List<String>> stateToDistricts = const {};

  static const regionToIncidentTypes = <String, List<String>>{
    'South': ['Cyclones', 'Floods', 'Landslides', 'Forest Fires', 'Tsunami', 'Earthquakes'],
    'East': ['Floods', 'Cyclones', 'Landslides', 'Earthquakes', 'Infrastructure Damage'],
    'Northeast': ['Floods', 'Landslides', 'Earthquakes', 'Infrastructure Damage', 'Cyclones'],
    'Central': ['Floods', 'Landslides', 'Forest Fires', 'Dust Storms', 'Rain Storms'],
    'West': ['Cyclones', 'Floods', 'Landslides', 'Infrastructure Damage'],
    'North': ['Floods', 'Landslides', 'Earthquakes', 'Snow Storms', 'Infrastructure Damage'],
  };

  /// States/UTs with a coastline: only these show wave height on the map sheet.
  static const coastalStates = {
    'Andhra Pradesh', 'Karnataka', 'Kerala', 'Tamil Nadu', 'Andaman & Nicobar Islands', 'Lakshadweep',
    'Puducherry', 'Odisha', 'West Bengal', 'Goa', 'Gujarat', 'Maharashtra',
    'Dadra & Nagar Haveli and Daman & Diu',
  };

  static const _stateAliases = {
    'nct of delhi': 'Delhi',
    'orissa': 'Odisha',
    'pondicherry': 'Puducherry',
    'daman and diu': 'Dadra & Nagar Haveli and Daman & Diu',
    'dadra and nagar haveli': 'Dadra & Nagar Haveli and Daman & Diu',
  };

  static Future<void> load() async {
    final j = jsonDecode(await rootBundle.loadString('assets/region_data.json')) as Map<String, dynamic>;
    Map<String, List<String>> lists(String k) =>
        {for (final e in (j[k] as Map<String, dynamic>).entries) e.key: List<String>.from(e.value as List)};
    regionToStates = lists('regionToStates');
    stateToDistricts = lists('stateToDistricts');
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'\b(district|division)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? regionOf(String state) {
    for (final e in regionToStates.entries) {
      if (e.value.contains(state)) return e.key;
    }
    return null;
  }

  /// Maps free text from a geocoder ("NCT of Delhi", "Jammu and Kashmir") to our canonical state name.
  static String? matchState(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = _norm(raw);
    return _stateAliases[n] ?? stateToDistricts.keys.where((s) => _norm(s) == n).firstOrNull;
  }

  /// Maps "Kamrup Metropolitan District" to the canonical district in [state], or null if unknown.
  static String? matchDistrict(String state, String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = _norm(raw);
    final ds = stateToDistricts[state] ?? const [];
    return ds.where((d) => _norm(d) == n).firstOrNull ??
        ds.where((d) => n.contains(_norm(d)) || _norm(d).contains(n)).firstOrNull;
  }
}
