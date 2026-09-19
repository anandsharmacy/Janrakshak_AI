import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/providers.dart';
import '../../data/store.dart';
import '../../data/supabase_config.dart';

const flushTask = 'flush-pending-reports';

class Report {
  Report({
    required this.id,
    required this.state,
    required this.district,
    required this.types,
    required this.description,
    this.lat,
    this.lng,
    this.severity,
    this.userId,
    this.mediaPaths = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// `id` is a client-generated UUID and doubles as the row id, so a retry can never create a duplicate.
  final String id, state, district, description;
  final String? userId; // reporter; a queued report is only sent by that same signed-in user
  final List<String> types;
  final double? lat, lng;
  final String? severity;
  final List<String> mediaPaths;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id, 'state': state, 'district': district, 'types': types, 'description': description,
        'lat': lat, 'lng': lng, 'severity': severity, 'uid': userId, 'media': mediaPaths, 'createdAt': createdAt.toIso8601String(),
      };

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'], state: j['state'], district: j['district'], types: List<String>.from(j['types']),
        description: j['description'], lat: (j['lat'] as num?)?.toDouble(), lng: (j['lng'] as num?)?.toDouble(),
        severity: j['severity'], userId: j['uid'], mediaPaths: List<String>.from(j['media']), createdAt: DateTime.parse(j['createdAt']),
      );

  String toJsonString() => jsonEncode(toJson());

  Report withMedia(List<String> paths) => Report(
      id: id, state: state, district: district, types: types, description: description, lat: lat, lng: lng,
      severity: severity, userId: userId, mediaPaths: paths, createdAt: createdAt);
}

// The incident_type_enum has no cyclone/fire/storm values; those go in as 'other' with the real types in the title.
const _category = {'Floods': 'flood', 'Landslides': 'landslide', 'Infrastructure Damage': 'infrastructure_damage'};
const _mime = {
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.heic': 'image/heic',
  '.mp4': 'video/mp4', '.mov': 'video/quicktime', '.3gp': 'video/3gpp',
};

/// Uploads media to the private incident-media bucket (under `<uid>/<report id>/`), then inserts the road_incidents row
/// as pending/unverified (the only thing RLS lets a citizen do). Both steps tolerate a repeat, so retries are safe.
// ponytail: files with an extension outside _mime are skipped (the bucket would reject them); the upload API has no
// byte-progress callback, so progress is per file.
Future<void> sendReport(Report r, {void Function(int index, double progress)? onProgress}) async {
  final sb = Supabase.instance.client;
  final uid = sb.auth.currentUser?.id;
  if (uid == null || (r.userId != null && r.userId != uid)) {
    throw StateError('Sign in as the reporter to send this report.');
  }
  final prefix = '$uid/${r.id}';
  var uploaded = 0;
  for (var i = 0; i < r.mediaPaths.length; i++) {
    final path = r.mediaPaths[i];
    final mime = _mime[p.extension(path).toLowerCase()];
    if (mime == null) continue;
    onProgress?.call(i, 0.15);
    try {
      await sb.storage
          .from('incident-media')
          .upload('$prefix/${p.basename(path)}', File(path), fileOptions: FileOptions(contentType: mime));
    } on StorageException catch (e) {
      if (e.statusCode != '409') rethrow; // 409: uploaded by an earlier attempt
    }
    onProgress?.call(i, 1);
    uploaded++;
  }
  try {
    await sb.from('road_incidents').insert({
      'id': r.id,
      'reported_by': uid,
      'category': r.types.map((t) => _category[t]).nonNulls.firstOrNull ?? 'other',
      'title': '${r.types.join(', ')} - ${r.district}',
      'description': r.description,
      'severity': ?r.severity?.toLowerCase(), // Low/Moderate/High/Critical match priority_enum
      'district': r.district,
      'state': r.state.replaceAll(' & ', ' and '), // the website uses the CSV spelling
      if (r.lat != null && r.lng != null) 'geometry': 'SRID=4326;POINT(${r.lng} ${r.lat})',
      if (uploaded > 0) 'media_path': '$prefix/',
      'sync_source': 'citizen_app',
    });
  } on PostgrestException catch (e) {
    if (e.code != '23505') rethrow; // duplicate id: an earlier attempt already inserted it
  }
}

enum SubmitResult { sent, queued }

Future<SubmitResult> submitReport(Report r, {void Function(int, double)? onProgress}) async {
  if (await isOnline()) {
    try {
      await sendReport(r, onProgress: onProgress);
      return SubmitResult.sent;
    } on PostgrestException {
      rethrow; // the server refused it: queueing would only retry a rejection forever
    } on StorageException {
      rethrow;
    } catch (_) {/* network failure or signed out: fall through to the offline queue */}
  }
  // image_picker paths live in the OS cache and can be purged before the retry runs.
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'pending_media', r.id));
  await dir.create(recursive: true);
  final kept = [
    for (final path in r.mediaPaths) (await File(path).copy(p.join(dir.path, p.basename(path)))).path,
  ];
  await Store.pendingReports.put(r.id, r.withMedia(kept).toJsonString());
  await Workmanager().registerOneOffTask(
    flushTask, flushTask,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
  );
  return SubmitResult.queued;
}

/// Sends every queued report; each Hive entry (and its copied media) is removed only on success.
typedef ReportSender = Future<void> Function(Report r);

Future<bool> flushPending({ReportSender send = sendReport}) async {
  for (final key in Store.pendingReports.keys.toList()) {
    try {
      final r = Report.fromJson(jsonDecode(Store.pendingReports.get(key)!));
      await send(r);
      await Store.pendingReports.delete(key);
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'pending_media', r.id));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {/* keep the entry; WorkManager backoff or the next reconnect retries it */}
  }
  return Store.pendingReports.isEmpty;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Store.init();
      await ensureSupabase(); // session is restored from local storage
      return await flushPending();
    } catch (_) {
      return false;
    }
  });
}

/// Foreground flush whenever connectivity comes back (WorkManager covers the app-closed case).
final reportFlushProvider = Provider<void>((ref) {
  ref.listen(onlineProvider, (_, next) {
    if (next.value == true) flushPending();
  }, fireImmediately: true);
});
