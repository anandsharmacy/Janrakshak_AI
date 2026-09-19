import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janrakshak_user/data/offline_tiles.dart';
import 'package:janrakshak_user/data/pmtiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'pmtiles_test.dart' show BytesSource, idBytes;

/// Reads fine until told to fail, to simulate a host that stops answering after the header.
class FlakySource extends BytesSource {
  FlakySource(super.bytes);
  bool failing = false;

  @override
  Future<Uint8List> read(int offset, int length) {
    if (failing) throw const SocketException('offline');
    return super.read(offset, length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final archive = File('test/fixtures/tiny.pmtiles').readAsBytesSync();
  final expected = jsonDecode(File('test/fixtures/tiny.expected.json').readAsStringSync()) as Map<String, dynamic>;
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('jr_pack'));
  tearDown(() => root.deleteSync(recursive: true));

  // A route through tiles that exist in the fixture at low zoom (it holds a random 20% of z0-9).
  const route = [LatLng(24.83, 92.78), LatLng(24.9, 92.9)];

  test('downloader copies planned tiles out of the archive, skips ones on disk, and reports empty ones as fine', () async {
    final reader = await PmTilesReader.open(BytesSource(archive));
    final plan = planCorridor(route, maxZoom: 9);
    var inArchive = 0;
    for (final (z, x, y) in plan.all) {
      if (await reader.tileRaw(z, x, y) != null) inArchive++;
    }
    expect(inArchive, greaterThan(0));
    expect(inArchive, lessThan(plan.count)); // some tiles are absent: must not count as failures

    final r1 = await OfflineDownloader(root: root.path, reader: reader).run(plan);
    expect(r1.failed, 0);
    expect(r1.done, plan.count);
    final files = root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.tile')).length;
    expect(files, inArchive);
    expect(root.listSync(recursive: true).where((e) => e.path.endsWith('.part')), isEmpty);

    final r2 = await OfflineDownloader(root: root.path, reader: await PmTilesReader.open(BytesSource(archive))).run(plan);
    expect(r2.failed, 0);
    expect(r2.bytes, 0); // every stored tile was skipped: no tile data fetched a second time
  });

  test('downloader gives up early when the host stops answering', () async {
    final src = FlakySource(archive);
    final reader = await PmTilesReader.open(src);
    src.failing = true;
    final r = await OfflineDownloader(root: root.path, reader: reader).run(planCorridor(route, maxZoom: 9));
    expect(r.error, isNotNull);
    expect(r.done, lessThan(planCorridor(route, maxZoom: 9).count));
  });

  test('provider: downloaded tile wins over the network, archive is the fallback, gaps are 404', () async {
    final present = (expected['present'] as List).first as List;
    final src = FlakySource(archive);
    final provider = PmTilesVectorProvider(root.path, src);

    // served from the archive
    final z = present[0] as int, x = present[1] as int, y = present[2] as int;
    expect(await provider.provide(TileIdentity(z, x, y)), idBytes(present[3]));

    // a stored file is used even when the network is gone, and gzip is unpacked
    src.failing = true;
    final f = tileFile(root.path, 5, 1, 2)..createSync(recursive: true);
    f.writeAsBytesSync(gzip.encode([9, 9, 9]));
    expect(await provider.provide(TileIdentity(5, 1, 2)), [9, 9, 9]);

    // not stored + network down -> retryable error; tile outside the zoom range -> permanent
    await expectLater(provider.provide(TileIdentity(6, 3, 3)),
        throwsA(isA<ProviderException>().having((e) => e.retryable, 'retryable', Retryable.retry)));
    await expectLater(provider.provide(TileIdentity(kPmtilesMaxZoom + 1, 0, 0)),
        throwsA(isA<ProviderException>().having((e) => e.retryable, 'retryable', Retryable.none)));

    // network back: a tile the archive does not contain is a 404, not a retry loop
    src.failing = false;
    final absent = (expected['absent'] as List).first as List;
    await expectLater(provider.provide(TileIdentity(absent[0], absent[1], absent[2])),
        throwsA(isA<ProviderException>().having((e) => e.statusCode, 'status', 404)));
  });

  test('the app style parses and only asks for the OpenMapTiles source', () async {
    final style = jsonDecode(File('assets/basemap/style.json').readAsStringSync()) as Map<String, dynamic>;
    expect(style.containsKey('sprite'), isFalse); // no remote sprite/glyph/tile URLs: it must work offline
    expect(style.containsKey('glyphs'), isFalse);
    final theme = vtr.ThemeReader().read(style);
    expect(theme.tileSources, {'openmaptiles'});
    expect(theme.layers.length, greaterThan(30));
  });

  testWidgets('a real Silchar tile renders through the real style (roads, water, buildings drawn)', (tester) async {
    final style = jsonDecode(File('assets/basemap/style.json').readAsStringSync()) as Map<String, dynamic>;
    final theme = vtr.ThemeReader().read(style);
    final bytes = gunzipIfNeeded(File('test/fixtures/silchar_z13.mvt.gz').readAsBytesSync());
    final tile = vtr.TileFactory(theme, const vtr.Logger.noop()).create(vtr.VectorTileReader().read(bytes));
    final tileset = vtr.Tileset({'openmaptiles': tile});

    final png = await tester.runAsync(() async {
      final image = await vtr.ImageRenderer(theme: theme, scale: 2)
          .render(vtr.TileSource(tileset: tileset), zoom: 13);
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final colours = <int>{};
      for (var i = 0; i < rgba.length; i += 4) {
        colours.add(rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2]);
      }
      final out = File('build/test_render/silchar_z13.png')..createSync(recursive: true);
      out.writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      return colours.length;
    });
    expect(png, greaterThan(8), reason: 'a blank/one-colour tile means the style did not match the data');
  });

  test('archive probe: missing file falls back to OSM, but being offline keeps the offline map', () async {
    HttpRangeSource src(http.Client c) => HttpRangeSource('https://example.test/x.pmtiles', client: c);
    expect(await archiveReachable(src(MockClient((_) async => http.Response.bytes([1], 206)))), isTrue);
    expect(await archiveReachable(src(MockClient((_) async => http.Response('Not found', 404)))), isFalse); // not uploaded yet
    expect(await archiveReachable(src(MockClient((_) async => http.Response.bytes([1], 200)))), isFalse); // no range support
    expect(await archiveReachable(src(MockClient((_) async => throw const SocketException('offline')))), isTrue);
  });
}
