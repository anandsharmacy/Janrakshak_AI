import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Minimal reader for PMTiles v3 (https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md): a whole tile pyramid in
/// one file, so it can be hosted as a single static object and read with HTTP range requests, no tile server needed.

abstract class ByteSource {
  /// Up to [length] bytes from [offset] (fewer at end of file).
  Future<Uint8List> read(int offset, int length);
}

/// The host answered, but not with the bytes asked for (404 file missing, 403, or 200 = Range ignored).
class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode, this.url);
  final int statusCode;
  final Uri url;

  @override
  String toString() => 'HTTP $statusCode from $url (expected 206 Partial Content: the file must exist and the host must support range requests)';
}

/// Range requests against a static URL (Supabase Storage, S3, any CDN). Refuses to buffer a body when the server
/// ignores `Range` (it would send the whole file for every tile).
class HttpRangeSource implements ByteSource {
  HttpRangeSource(this.url, {http.Client? client, this.headers = const {}}) : _client = client ?? http.Client();
  final String url;
  final Map<String, String> headers;
  final http.Client _client;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final req = http.Request('GET', Uri.parse(url))
      ..headers.addAll(headers)
      ..headers['Range'] = 'bytes=$offset-${offset + length - 1}';
    final res = await _client.send(req).timeout(const Duration(seconds: 20));
    if (res.statusCode != 206) {
      await res.stream.listen((_) {}).cancel(); // do not download the body
      throw HttpStatusException(res.statusCode, req.url);
    }
    return Uint8List.fromList(await res.stream.toBytes());
  }

  void close() => _client.close();
}

/// Position of a tile in the archive's Hilbert-curve ordering (spec: "Tile IDs").
int tileId(int z, int x, int y) {
  var acc = 0;
  for (var i = 0; i < z; i++) {
    acc += (1 << i) * (1 << i);
  }
  final n = 1 << z;
  var d = 0;
  for (var s = n ~/ 2; s > 0; s ~/= 2) {
    final rx = (x & s) > 0 ? 1 : 0;
    final ry = (y & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        x = n - 1 - x;
        y = n - 1 - y;
      }
      final t = x;
      x = y;
      y = t;
    }
  }
  return acc + d;
}

const compressionNone = 1, compressionGzip = 2;

class PmTilesHeader {
  PmTilesHeader(ByteData b)
      : rootOffset = b.getUint64(8, Endian.little),
        rootLength = b.getUint64(16, Endian.little),
        leafOffset = b.getUint64(40, Endian.little),
        dataOffset = b.getUint64(56, Endian.little),
        internalCompression = b.getUint8(97),
        tileCompression = b.getUint8(98),
        tileType = b.getUint8(99),
        minZoom = b.getUint8(100),
        maxZoom = b.getUint8(101);

  static const size = 127;
  final int rootOffset, rootLength, leafOffset, dataOffset;
  final int internalCompression, tileCompression, tileType, minZoom, maxZoom;
}

class _Entry {
  const _Entry(this.tileId, this.offset, this.length, this.runLength);
  final int tileId, offset, length, runLength; // runLength 0 = pointer to a leaf directory
}

Uint8List gunzipIfNeeded(Uint8List b) =>
    b.length > 2 && b[0] == 0x1f && b[1] == 0x8b ? Uint8List.fromList(gzip.decode(b)) : b;

class PmTilesReader {
  PmTilesReader._(this._src, this.header, Uint8List head) {
    _dirs[header.rootOffset] = Future.value(_decode(head.sublist(header.rootOffset, header.rootOffset + header.rootLength)));
  }

  final ByteSource _src;
  final PmTilesHeader header;
  final _dirs = <int, Future<List<_Entry>>>{}; // directory offset -> parsed entries (in-flight fetches are shared)

  static Future<PmTilesReader> open(ByteSource src) async {
    final head = await src.read(0, 16384); // the spec keeps the header and root directory inside the first 16 KiB
    if (head.length < PmTilesHeader.size || String.fromCharCodes(head.sublist(0, 7)) != 'PMTiles' || head[7] != 3) {
      throw const FormatException('Not a PMTiles v3 archive');
    }
    final header = PmTilesHeader(ByteData.sublistView(head));
    if (header.tileType != 1) throw const FormatException('Only vector (MVT) PMTiles are supported');
    return PmTilesReader._(src, header, head);
  }

  List<_Entry> _decode(Uint8List raw) {
    final b = header.internalCompression == compressionGzip ? gzip.decode(raw) : raw;
    var pos = 0;
    int varint() {
      var result = 0, shift = 0;
      while (true) {
        final byte = b[pos++];
        result |= (byte & 0x7f) << shift;
        if (byte < 0x80) return result;
        shift += 7;
      }
    }

    final n = varint();
    final ids = List.filled(n, 0);
    var last = 0;
    for (var i = 0; i < n; i++) {
      last += varint();
      ids[i] = last;
    }
    final runs = [for (var i = 0; i < n; i++) varint()];
    final lens = [for (var i = 0; i < n; i++) varint()];
    final out = <_Entry>[];
    for (var i = 0; i < n; i++) {
      final v = varint();
      final off = v == 0 && i > 0 ? out[i - 1].offset + out[i - 1].length : v - 1; // 0 = directly after the previous entry
      out.add(_Entry(ids[i], off, lens[i], runs[i]));
    }
    return out;
  }

  Future<List<_Entry>> _dir(int offset, int length) =>
      _dirs[offset] ??= _src.read(offset, length).then(_decode).catchError((Object e) {
        _dirs.remove(offset); // do not cache a failed fetch
        throw e;
      });

  /// The tile exactly as stored (gzip for OpenMapTiles builds), or null if the archive has no such tile.
  Future<Uint8List?> tileRaw(int z, int x, int y) async {
    final id = tileId(z, x, y);
    var offset = header.rootOffset, length = header.rootLength;
    for (var depth = 0; depth < 4; depth++) {
      final dir = await _dir(offset, length);
      var lo = 0, hi = dir.length - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        dir[mid].tileId <= id ? lo = mid + 1 : hi = mid - 1;
      }
      if (hi < 0) return null;
      final e = dir[hi];
      if (e.runLength > 0) {
        return id < e.tileId + e.runLength ? _src.read(header.dataOffset + e.offset, e.length) : null;
      }
      offset = header.leafOffset + e.offset; // leaf directory pointer: descend
      length = e.length;
    }
    return null;
  }

  /// Decompressed MVT bytes, ready for the renderer.
  Future<Uint8List?> tile(int z, int x, int y) async {
    final raw = await tileRaw(z, x, y);
    return raw == null ? null : gunzipIfNeeded(raw);
  }
}
