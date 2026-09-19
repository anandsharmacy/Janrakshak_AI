import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/offline_tiles.dart';
import '../../data/pmtiles.dart';
import '../../data/store.dart';
import 'routing.dart';
import 'trip_controller.dart';

class OfflineState {
  const OfflineState({this.busy = false, this.done = 0, this.total = 0, this.bytes = 0, this.message, this.isError = false});
  final bool busy, isError;
  final int done, total, bytes;
  final String? message;
}

class OfflineController extends Notifier<OfflineState> {
  OfflineDownloader? _dl;

  @override
  OfflineState build() => const OfflineState();

  /// Corridor around the checked route (original and diversion) or, before a check, the plain route between the endpoints.
  Future<OfflinePlan> plan() async {
    final t = ref.read(tripControllerProvider);
    final pts = t.hasResult ? [...t.original!.points, ...?t.diverted?.points] : (await fetchRoute([t.from!.pos, t.to!.pos])).points;
    return planCorridor(pts);
  }

  Future<void> download(OfflinePlan plan, String label) async {
    final root = OfflineTiles.root;
    if (root == null) return;
    state = OfflineState(busy: true, total: plan.count);
    final source = HttpRangeSource(kPmtilesUrl);
    try {
      final dl = _dl = OfflineDownloader(root: root, reader: await PmTilesReader.open(source));
      final r = await dl.run(plan, onProgress: (d, t, b) {
        if (d % 20 == 0 || d == t) state = OfflineState(busy: true, done: d, total: t, bytes: b); // throttle rebuilds
      });
      if (r.error != null) {
        state = OfflineState(message: r.error, isError: true);
      } else if (r.cancelled) {
        state = OfflineState(message: 'Download cancelled. ${r.done} tiles were kept.');
      } else {
        await addOfflineArea(OfflineArea(label, r.done - r.failed, r.bytes, plan.maxZoom));
        state = OfflineState(
          message: r.failed == 0
              ? 'Map saved for offline use.'
              : 'Map saved, but ${r.failed} tiles could not be fetched and stay online-only.',
        );
      }
    } catch (e) {
      state = OfflineState(message: "Couldn't download the map: $e", isError: true);
    } finally {
      source.close();
      _dl = null;
    }
  }

  void cancel() => _dl?.cancel();

  Future<void> clear() async {
    await clearOfflineTiles();
    state = const OfflineState(message: 'Offline maps deleted.');
  }
}

final offlineControllerProvider = NotifierProvider<OfflineController, OfflineState>(OfflineController.new);

final offlineAreasProvider = StreamProvider<List<OfflineArea>>((ref) async* {
  yield readOfflineAreas();
  yield* Store.settings.watch(key: offlineAreasKey).map((_) => readOfflineAreas());
});
