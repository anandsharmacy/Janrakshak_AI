import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'pmtiles.dart';
import 'store.dart';

/// Self-hosted basemap: one PMTiles file (built by tools/basemap/build.sh, hosted on Supabase Storage or any static host).
/// Defaults to the project's public `basemap` bucket. Override with `--dart-define=PMTILES_URL=...`, or set it empty to
/// disable. While the file is missing (not uploaded yet) or unset, the app shows the public OpenStreetMap raster server
/// for display only (its usage policy forbids bulk/offline downloads).
const kPmtilesUrl = String.fromEnvironment('PMTILES_URL',
    defaultValue: 'https://sjcqwxthimfuxmrodsbs.supabase.co/storage/v1/object/public/basemap/india.pmtiles');

/// Deepest zoom stored in the archive; must match `MAXZOOM` in tools/basemap/build.sh. The whole map shares one maximum
/// zoom (a missing tile is blank, it is not replaced by a coarser one; overzoom only works past this level), and 9 is the
/// deepest level at which ALL of India fits the 50 MB free-plan upload limit (34 MiB; zoom 10 is 85 MiB, zoom 12 530 MiB).
const kPmtilesMaxZoom = int.fromEnvironment('PMTILES_MAX_ZOOM', defaultValue: 9);
const kMinDownloadZoom = 5;
const kOsmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const kAttribution = 'OpenMapTiles © OpenStreetMap contributors'; // the attribution widget adds the leading ©
const _kUserAgent = 'com.janrakshak.janrakshak_user';

/// True once the hosted archive was found (or could not be checked because the phone is offline).
bool get offlineMapsEnabled => OfflineTiles.provider != null;

/// Map zoom used while navigating: one level past the deepest stored tiles.
double get navZoom => kPmtilesMaxZoom + 1.0;

// ---- on-disk cache of downloaded tiles ------------------------------------------------------------------------

class OfflineTiles {
  static String? root; // null until init (tests, first frame)

  /// False after several network failures in a row while reading tiles (offline, host down). Not touched by tiles that
  /// are simply missing from the archive, nor by tiles served from disk.
  static final tilesReachable = ValueNotifier<bool>(true);
  static PmTilesVectorProvider? provider;
  static vtr.Theme? theme;

  static int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// One folder per archive URL, so pointing the app at a different file never mixes tiles.
  static Future<void> init({ByteSource? probeSource}) async {
    if (kPmtilesUrl.isEmpty) return;
    if (!await archiveReachable(probeSource ?? HttpRangeSource(kPmtilesUrl))) return; // file not uploaded yet: keep the OSM map
    final id = _fnv(kPmtilesUrl.split('?').first).toRadixString(16);
    root = p.join((await getApplicationDocumentsDirectory()).path, 'offline_tiles', id);
    theme = vtr.ThemeReader().read(jsonDecode(await rootBundle.loadString('assets/basemap/style.json')) as Map<String, dynamic>);
    provider = PmTilesVectorProvider(root!, HttpRangeSource(kPmtilesUrl, headers: const {'User-Agent': _kUserAgent}));
  }
}

/// False only when the host answers but the archive is not there (404, or no range support). A phone that is offline
/// (or a slow start) counts as reachable, so tiles it already downloaded keep working.
Future<bool> archiveReachable(ByteSource source) async {
  try {
    await source.read(0, 16).timeout(const Duration(seconds: 3));
    return true;
  } on HttpStatusException {
    return false;
  } catch (_) {
    return true;
  }
}

File tileFile(String root, int z, int x, int y) => File(p.join(root, '$z', '$x', '$y.tile'));

/// Serves a downloaded tile from disk when present, otherwise reads it from the hosted archive (HTTP range request).
class PmTilesVectorProvider extends VectorTileProvider {
  PmTilesVectorProvider(this.root, this.source);
  final String? root;
  final ByteSource source;
  Future<PmTilesReader>? _reader;
  var _networkFailures = 0;

  /// Opened lazily and retried after a failure, so starting offline and coming online later just works.
  Future<PmTilesReader> get _open => _reader ??= PmTilesReader.open(source).catchError((Object e) {
        _reader = null;
        throw e;
      });

  @override
  int get maximumZoom => kPmtilesMaxZoom;
  @override
  int get minimumZoom => 0;
  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    if (tile.z > maximumZoom || tile.z < minimumZoom || !tile.isValid()) {
      throw ProviderException(message: 'Invalid tile coordinates $tile', retryable: Retryable.none, statusCode: 400);
    }
    if (root != null) {
      final f = tileFile(root!, tile.z, tile.x, tile.y);
      if (f.existsSync()) return gunzipIfNeeded(await f.readAsBytes());
    }
    final Uint8List? bytes;
    try {
      bytes = await (await _open).tile(tile.z, tile.x, tile.y);
    } catch (e) {
      if (++_networkFailures >= 3) OfflineTiles.tilesReachable.value = false;
      throw ProviderException(message: 'Cannot read tile $tile: $e', retryable: Retryable.retry);
    }
    _networkFailures = 0;
    OfflineTiles.tilesReachable.value = true; // the host answered (even "no such tile")
    if (bytes == null) throw ProviderException(message: 'No tile $tile', retryable: Retryable.none, statusCode: 404);
    return bytes;
  }
}

// ---- corridor planning --------------------------------------------------------------------------------------------

(int, int) tileOf(LatLng pt, int z) {
  final n = 1 << z;
  final lat = pt.latitude.clamp(-85.0511, 85.0511) * pi / 180;
  final x = ((pt.longitude + 180) / 360 * n).floor().clamp(0, n - 1);
  final y = ((1 - log(tan(lat) + 1 / cos(lat)) / pi) / 2 * n).floor().clamp(0, n - 1);
  return (x, y);
}

int _pack(int x, int y) => (x << 26) | y;

class OfflinePlan {
  const OfflinePlan(this.minZoom, this.maxZoom, this.tiles);
  final int minZoom, maxZoom;
  final Map<int, Set<int>> tiles; // zoom -> packed (x, y)

  int get count => tiles.values.fold(0, (a, s) => a + s.length);
  int get estimatedBytes => count * 16000; // measured: ~15-20 KB per tile (gzip'd OpenMapTiles vectors) along roads and towns

  Iterable<(int, int, int)> get all sync* {
    for (final e in tiles.entries) {
      for (final k in e.value) {
        yield (e.key, k >> 26, k & 0x3ffffff);
      }
    }
  }
}

/// Tiles within [buffer] tiles of the route at every zoom from [kMinDownloadZoom] up to the deepest level that keeps the
/// total under [maxTiles] (about 160 MB) (so a 2,000 km trip gets a shallower map than a 50 km one).
OfflinePlan planCorridor(List<LatLng> route, {int maxTiles = 10000, int buffer = 1, int maxZoom = kPmtilesMaxZoom}) {
  final perZoom = <int, Set<int>>{};
  for (var z = kMinDownloadZoom; z <= maxZoom; z++) {
    final core = <int>{};
    (int, int)? prev;
    for (var i = 0; i < route.length; i++) {
      final pt = route[i];
      final t = tileOf(pt, z);
      if (prev != null) {
        final steps = max((t.$1 - prev.$1).abs(), (t.$2 - prev.$2).abs());
        final a = route[i - 1];
        for (var s = 1; s < steps; s++) {
          // sparse points (straight-line fallback): fill the tiles in between
          final f = s / steps;
          final m = tileOf(LatLng(a.latitude + (pt.latitude - a.latitude) * f, a.longitude + (pt.longitude - a.longitude) * f), z);
          core.add(_pack(m.$1, m.$2));
        }
      }
      core.add(_pack(t.$1, t.$2));
      prev = t;
    }
    final n = 1 << z, out = <int>{};
    for (final k in core) {
      final x = k >> 26, y = k & 0x3ffffff;
      for (var dx = -buffer; dx <= buffer; dx++) {
        for (var dy = -buffer; dy <= buffer; dy++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < n && ny < n) out.add(_pack(nx, ny));
        }
      }
    }
    perZoom[z] = out;
  }
  var total = 0, maxZ = kMinDownloadZoom;
  for (var z = kMinDownloadZoom; z <= maxZoom; z++) {
    total += perZoom[z]!.length;
    if (total > maxTiles && z > kMinDownloadZoom + 3) break;
    maxZ = z;
  }
  return OfflinePlan(kMinDownloadZoom, maxZ, {for (var z = kMinDownloadZoom; z <= maxZ; z++) z: perZoom[z]!});
}

// ---- download -----------------------------------------------------------------------------------------------------

class DownloadResult {
  const DownloadResult({required this.done, required this.failed, required this.bytes, this.error, this.cancelled = false});
  final int done, failed, bytes;
  final String? error;
  final bool cancelled;
}

/// Copies every planned tile out of the hosted archive into [root] (one range request per tile, directories are cached).
class OfflineDownloader {
  OfflineDownloader({required this.root, required this.reader, this.concurrency = 4});
  final String root;
  final PmTilesReader reader;
  final int concurrency;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Skips tiles already on disk. Gives up early when the first tiles all fail (wrong URL, host without range
  /// support) instead of hammering the host. A tile the archive simply does not contain (outside its extent) is fine.
  Future<DownloadResult> run(OfflinePlan plan, {void Function(int done, int total, int bytes)? onProgress}) async {
    final queue = plan.all.iterator;
    final total = plan.count;
    var done = 0, failed = 0, bytes = 0, attempted = 0, answered = 0;
    String? error;

    (int, int, int)? next() => queue.moveNext() ? queue.current : null;

    Future<void> worker() async {
      while (!_cancelled && error == null) {
        final t = next();
        if (t == null) return;
        final file = tileFile(root, t.$1, t.$2, t.$3);
        if (file.existsSync()) {
          done++;
          onProgress?.call(done, total, bytes);
          continue;
        }
        attempted++;
        try {
          final got = await reader.tileRaw(t.$1, t.$2, t.$3);
          answered++;
          if (got != null) {
            await file.parent.create(recursive: true);
            final tmp = File('${file.path}.part');
            await tmp.writeAsBytes(got);
            await tmp.rename(file.path);
            bytes += got.length;
          }
        } catch (_) {
          failed++;
          if (answered == 0 && attempted >= 8) {
            error = "Couldn't read the map file. Check PMTILES_URL and that the host supports range requests.";
          }
        }
        done++;
        onProgress?.call(done, total, bytes);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    return DownloadResult(done: done, failed: failed, bytes: bytes, error: error, cancelled: _cancelled);
  }
}

// ---- what is stored -----------------------------------------------------------------------------------------------

class OfflineArea {
  const OfflineArea(this.label, this.tiles, this.bytes, this.maxZoom);
  final String label;
  final int tiles, bytes, maxZoom;

  Map<String, dynamic> toJson() => {'label': label, 'tiles': tiles, 'bytes': bytes, 'maxZoom': maxZoom};
  factory OfflineArea.fromJson(Map<String, dynamic> j) => OfflineArea(j['label'], j['tiles'], j['bytes'], j['maxZoom']);
}

const offlineAreasKey = 'offline_areas';

List<OfflineArea> readOfflineAreas() {
  final raw = Store.settings.get(offlineAreasKey);
  return raw == null ? const [] : [for (final j in jsonDecode(raw) as List) OfflineArea.fromJson(j as Map<String, dynamic>)];
}

Future<void> addOfflineArea(OfflineArea a) =>
    Store.settings.put(offlineAreasKey, jsonEncode([...readOfflineAreas(), a].map((e) => e.toJson()).toList()));

// ponytail: tiles are shared between overlapping areas, so deletion is all-or-nothing; track per-area tile lists if per-trip delete is needed.
Future<void> clearOfflineTiles() async {
  final r = OfflineTiles.root;
  if (r != null && Directory(r).existsSync()) await Directory(r).delete(recursive: true);
  await Store.settings.delete(offlineAreasKey);
}
