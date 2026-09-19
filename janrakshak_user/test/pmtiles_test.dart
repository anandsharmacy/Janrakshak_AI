import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janrakshak_user/data/offline_tiles.dart' show kPmtilesMaxZoom, tileOf;
import 'package:latlong2/latlong.dart';
import 'package:janrakshak_user/data/pmtiles.dart';

class BytesSource implements ByteSource {
  BytesSource(this.bytes);
  final Uint8List bytes;
  int reads = 0;

  @override
  Future<Uint8List> read(int offset, int length) async {
    reads++;
    return bytes.sublist(offset, (offset + length).clamp(0, bytes.length));
  }
}

String sha1Hex(Uint8List b) => sha1.convert(b).toString();

Uint8List idBytes(int id) => Uint8List.fromList([id >> 24 & 255, id >> 16 & 255, id >> 8 & 255, id & 255]);

void main() {
  final archive = File('test/fixtures/tiny.pmtiles').readAsBytesSync();
  final expected = jsonDecode(File('test/fixtures/tiny.expected.json').readAsStringSync()) as Map<String, dynamic>;

  test('tile ids match the reference implementation', () {
    for (final r in expected['tileIds'] as List) {
      expect(tileId(r[0], r[1], r[2]), r[3], reason: 'z${r[0]} x${r[1]} y${r[2]}');
    }
  });

  test('reads tiles through leaf directories, and reports missing tiles as null', () async {
    final src = BytesSource(archive);
    final reader = await PmTilesReader.open(src);
    expect(reader.header.maxZoom, 9);
    expect(reader.header.rootLength, lessThan(200)); // tiny root: everything below is reached via leaf directories
    for (final r in expected['present'] as List) {
      final tile = await reader.tile(r[0], r[1], r[2]);
      expect(tile, isNotNull, reason: 'z${r[0]} x${r[1]} y${r[2]} should exist');
      expect(tile, idBytes(r[3]));
    }
    for (final r in expected['absent'] as List) {
      expect(await reader.tile(r[0], r[1], r[2]), isNull, reason: 'z${r[0]} x${r[1]} y${r[2]} should be absent');
    }
    expect(await reader.tile(12, 0, 0), isNull); // beyond the archive's zoom range
  });

  test('a directory is fetched once, however many tiles use it', () async {
    final src = BytesSource(archive);
    final reader = await PmTilesReader.open(src);
    final r = (expected['present'] as List).first as List;
    await reader.tile(r[0], r[1], r[2]);
    final after = src.reads;
    await reader.tile(r[0], r[1], r[2]);
    expect(src.reads - after, 1); // only the tile data read; directories came from memory
  });

  test('rejects data that is not PMTiles v3', () async {
    expect(PmTilesReader.open(BytesSource(Uint8List.fromList(List.filled(200, 7)))), throwsFormatException);
  });

  test('HTTP source sends a Range header, and refuses a server that ignores it', () async {
    final seen = <String>[];
    final ok = MockClient((req) async {
      seen.add(req.headers['Range']!);
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers['Range']!)!;
      final a = int.parse(m[1]!), b = int.parse(m[2]!);
      return http.Response.bytes(archive.sublist(a, (b + 1).clamp(0, archive.length)), 206);
    });
    final reader = await PmTilesReader.open(HttpRangeSource('https://example.test/x.pmtiles', client: ok));
    final r = (expected['present'] as List).last as List;
    expect(await reader.tile(r[0], r[1], r[2]), idBytes(r[3]));
    expect(seen.first, 'bytes=0-16383');
    expect(seen.length, greaterThan(2)); // header/root, a leaf directory, the tile

    final ignoresRange = MockClient((_) async => http.Response.bytes(archive, 200));
    expect(HttpRangeSource('https://example.test/x.pmtiles', client: ignoresRange).read(0, 100), throwsA(isA<HttpStatusException>()));
  });

  realArchiveTests();

  test('gunzipIfNeeded only touches gzip data', () {
    final raw = Uint8List.fromList([1, 2, 3, 4, 5]);
    expect(gunzipIfNeeded(raw), raw);
    expect(gunzipIfNeeded(Uint8List.fromList(gzip.encode(raw))), raw);
  });
}

/// Cross-check against the real Planetiler archive when it has been built (tools/basemap/build.sh); skipped otherwise.
/// Expected hashes come from the reference Python reader.
void realArchiveTests() {
  final f = File('tools/basemap/out/india.pmtiles');
  final samples = jsonDecode(File('test/fixtures/real_samples.json').readAsStringSync()) as List;
  test('real archive: every sampled tile matches the reference reader byte for byte', () async {
    final reader = await PmTilesReader.open(HttpRangeSource('unused', client: MockClient((req) async {
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers['Range']!)!;
      final raf = f.openSync();
      try {
        raf.setPositionSync(int.parse(m[1]!));
        return http.Response.bytes(raf.readSync(int.parse(m[2]!) - int.parse(m[1]!) + 1), 206);
      } finally {
        raf.closeSync();
      }
    })));
    expect(reader.header.maxZoom, kPmtilesMaxZoom);
    var present = 0;
    for (final s in samples) {
      final t = await reader.tile(s['z'], s['x'], s['y']);
      if (s['len'] == null) {
        expect(t, isNull, reason: '${s['name']} z${s['z']}');
      } else {
        present++;
        expect(t!.length, s['len'], reason: '${s['name']} z${s['z']}');
        expect(sha1Hex(t), s['sha1'], reason: '${s['name']} z${s['z']}');
      }
    }
    expect(present, greaterThan(20));
  }, skip: f.existsSync() ? false : 'build the basemap first: tools/basemap/build.sh');

  // Regression: the map once showed only the North East because the archive was built from that extract alone.
  test('real archive covers ALL of India: a tile exists at every zoom for cities in every region', () async {
    final raf = f.openSync();
    addTearDown(raf.closeSync);
    final reader = await PmTilesReader.open(FileSource(raf));
    const cities = {
      'Delhi': LatLng(28.61, 77.21), 'Mumbai': LatLng(19.08, 72.88), 'Bengaluru': LatLng(12.97, 77.59),
      'Hyderabad': LatLng(17.38, 78.48), 'Chennai': LatLng(13.08, 80.27), 'Kolkata': LatLng(22.57, 88.36),
      'Guwahati': LatLng(26.14, 91.74), 'Silchar': LatLng(24.83, 92.78), 'Srinagar': LatLng(34.08, 74.80),
      'Kochi': LatLng(9.93, 76.27), 'Ahmedabad': LatLng(23.02, 72.57), 'Port Blair': LatLng(11.62, 92.73),
    };
    expect(reader.header.maxZoom, kPmtilesMaxZoom);
    for (final e in cities.entries) {
      for (var z = 0; z <= kPmtilesMaxZoom; z++) {
        final (x, y) = tileOf(e.value, z);
        expect(await reader.tileRaw(z, x, y), isNotNull, reason: '${e.key} has no tile at z$z');
      }
    }
  }, skip: f.existsSync() ? false : 'build the basemap first: tools/basemap/build.sh');
}

/// Reads a local file in place (the real archive is far too big to load into memory).
class FileSource implements ByteSource {
  FileSource(this.raf);
  final RandomAccessFile raf;

  @override
  Future<Uint8List> read(int offset, int length) async {
    raf.setPositionSync(offset);
    return raf.readSync(length);
  }
}
