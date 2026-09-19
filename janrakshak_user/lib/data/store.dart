import 'package:hive_flutter/hive_flutter.dart';

/// All Hive boxes (String values holding JSON). Call [init] once per isolate.
class Store {
  static late Box<String> pendingReports, contacts, trips, settings;

  static Future<void> init() async {
    await Hive.initFlutter();
    pendingReports = await Hive.openBox<String>('pending_reports');
    contacts = await Hive.openBox<String>('contacts_cache');
    trips = await Hive.openBox<String>('recent_trips');
    settings = await Hive.openBox<String>('settings');
  }
}
