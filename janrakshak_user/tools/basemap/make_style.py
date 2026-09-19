"""Builds assets/basemap/style.json: OpenMapTiles "Dark Matter" (BSD-3 code, CC-BY 4.0 design, openmaptiles/dark-matter-gl-style)
retinted to the app's navy palette, with the parts the app cannot use removed (remote sprite/glyph/tile URLs, one-way arrows).
Usage: python3 tools/basemap/make_style.py"""
import json
import subprocess

SRC = "https://raw.githubusercontent.com/openmaptiles/dark-matter-gl-style/master/style.json"
OUT = "assets/basemap/style.json"

BG = "#0F1E33"  # AppColors.bgDark
PAINT = {
    "background": {"background-color": BG},
    "water": {"fill-color": "#163a5c"},
    "waterway": {"line-color": "#1d4a74"},
    "landcover_ice_shelf": {"fill-color": "#1a2c44"},
    "landcover_glacier": {"fill-color": "#1a2c44"},
    "landuse_residential": {"fill-color": "#132540"},
    "landcover_wood": {"fill-color": "#12312f"},
    "landuse_park": {"fill-color": "#12312f"},
    "building": {"fill-color": "#1a2e4a", "fill-outline-color": "#26406a"},
    "aeroway-area": {"fill-color": "#16263d"},
    "aeroway-taxiway": {"line-color": "#2c4060"},
    "aeroway-runway": {"line-color": "#3a4f70"},
    "aeroway-runway-casing": {"line-color": "rgba(10,21,36,0.8)"},
    "road_area_pier": {"fill-color": BG},
    "road_pier": {"line-color": BG},
    "highway_path": {"line-color": "#2c4060"},
    "highway_minor": {"line-color": "#34496b"},
    "highway_major_casing": {"line-color": "rgba(8,16,28,0.85)"},
    "highway_major_inner": {"line-color": "#5c7296"},
    "highway_major_subtle": {"line-color": "#465c80"},
    "highway_motorway_casing": {"line-color": "rgba(8,16,28,0.9)"},
    "highway_motorway_inner": {"line-color": "#b9c7dd"},
    "highway_motorway_subtle": {"line-color": "#465c80"},
    "railway": {"line-color": "#3d5273"},
    "railway_dashline": {"line-color": BG},
    "railway_minor": {"line-color": "#3d5273"},
    "railway_minor_dashline": {"line-color": BG},
    "railway_transit": {"line-color": "#3d5273"},
    "railway_transit_dashline": {"line-color": BG},
    "boundary_state": {"line-color": "#4a6390"},
    "boundary_country_z0-4": {"line-color": "#6a80a8"},
    "boundary_country_z5-": {"line-color": "#6a80a8"},
    "highway_name_other": {"text-color": "#9db0cc", "text-halo-color": BG},
    "highway_name_motorway": {"text-color": "#c3d0e4", "text-halo-color": BG},
    "water_name": {"text-color": "#6f9fd0", "text-halo-color": BG},
}
for pid in ("place_other", "place_suburb", "place_village", "place_town", "place_city", "place_city_large",
            "place_state", "place_country_other", "place_country_minor", "place_country_major"):
    PAINT[pid] = {"text-color": "#d5deec", "text-halo-color": BG}

style = json.loads(subprocess.run(["curl", "-fsSL", SRC], check=True, capture_output=True).stdout)  # curl: python.org builds often lack CA certs
style.pop("sprite", None)   # no remote sprite sheet / glyph server: the app renders text with Flutter fonts
style.pop("glyphs", None)
style["sources"] = {"openmaptiles": {"type": "vector"}}  # tiles come from the app's PMTiles provider, not a URL
style["name"] = "JanRakshak Dark"
style["id"] = "janrakshak-dark"
style["layers"] = [l for l in style["layers"] if not l["id"].startswith("road_oneway")]  # need sprite icons
missing = set(PAINT) - {l["id"] for l in style["layers"]}
assert not missing, f"style layers not found: {missing}"
for l in style["layers"]:
    l.setdefault("paint", {}).update(PAINT.get(l["id"], {}))

with open(OUT, "w") as f:
    json.dump(style, f, separators=(",", ":"))
print(f"{len(style['layers'])} layers -> {OUT}")
