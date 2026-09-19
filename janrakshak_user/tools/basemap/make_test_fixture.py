"""Writes test/fixtures/tiny.pmtiles (+ tiny.expected.json) with the reference Python writer.
A random 20% of all tiles at z0-9 (~70k entries); irregular tile ids keep the directory incompressible, so it spills into
leaf directories, which is the code path the real archive uses. A tile's content is its tile id as 4 big-endian bytes.
Usage: python3 -m venv v && v/bin/pip install pmtiles && v/bin/python tools/basemap/make_test_fixture.py"""
import json
import random
from pmtiles.writer import write
from pmtiles.tile import Compression, TileType, tileid_to_zxy, zxy_to_tileid

MAXZ = 9
N = sum(4**z for z in range(MAXZ + 1))
rnd = random.Random(7)
ids = [t for t in range(N) if rnd.random() < 0.2]
present_set = set(ids)

with write("test/fixtures/tiny.pmtiles") as w:
    for tid in ids:
        w.write_tile(tid, tid.to_bytes(4, "big"))
    w.finalize(
        {"tile_type": TileType.MVT, "tile_compression": Compression.NONE, "min_zoom": 0, "max_zoom": MAXZ,
         "min_lon_e7": -1800000000, "min_lat_e7": -850000000, "max_lon_e7": 1800000000, "max_lat_e7": 850000000,
         "center_zoom": 0, "center_lon_e7": 0, "center_lat_e7": 0},
        {"name": "fixture"},
    )

def zxy(t):
    z, x, y = tileid_to_zxy(t)
    return [z, x, y, t]

absent = rnd.sample([t for t in range(N) if t not in present_set], 300)
tile_id_refs = [[z, x, y, zxy_to_tileid(z, x, y)] for z, x, y in
                [(0, 0, 0), (1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0), (2, 0, 0)]
                + [(z, rnd.randrange(2**z), rnd.randrange(2**z)) for z in (3, 5, 7, 10, 14, 14, 22)]]
json.dump({"present": [zxy(t) for t in rnd.sample(ids, 300)], "absent": [zxy(t) for t in absent],
           "tileIds": tile_id_refs, "count": len(ids)}, open("test/fixtures/tiny.expected.json", "w"), separators=(",", ":"))
print("tiles:", len(ids))
