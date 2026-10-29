#!/usr/bin/env python3
"""
Writes App/Resources/Data/map/style.json and style-dark.json: the MapLibre styles for the offline Konstanz map,
in the design's light and dark palettes.

    python3 DataPipeline/map/make_style.py

Tiles: Protomaps basemap (OpenStreetMap), schema v4, cut to Konstanz with
    pmtiles extract https://build.protomaps.com/<yyyymmdd>.pmtiles konstanz.pmtiles --bbox=9.05,47.63,9.26,47.74 --maxzoom=15
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "App/Resources/Data/map"

# The design's map (screens 07, 09, 21; dark: 28): warm grey land, pale blue water, soft green parks,
# white streets on a grey casing, grey labels, blue water names. Values the design does not show
# (industry, hospitals, motorways, paths …) are picked to sit quietly between them.
LIGHT = dict(
    LAND="#F2F1ED", BUILDING="#E5E2DE", BUILDING_LINE="#D9D5CF", PARK="#D8E8D2", PARK_DARK="#CCE0C4",
    PITCH="#D0E5C8", EDUCATION="#EEE9DF", HOSPITAL="#F3E3E1", INDUSTRIAL="#EAE8E3", PEDESTRIAN="#F8F7F4",
    WATER="#B9D8E8", SHORE="#A9CDE0", ROAD="#FFFFFF", ROAD_CASING="#D5D3CF", HIGHWAY="#FFFFFF",
    HIGHWAY_CASING="#C9C6C1", PATH="#C4C0B8", RAIL="#B8B4AD", BORDER="#B9B2C6", DISTRICT_LABEL="#757575",
    STREET_LABEL="#5E6168", WATER_LABEL="#3F6FB0", HALO="#FFFFFF", WATER_HALO="#D6EBF8", POI_DEFAULT="#6B7A90",
)
DARK = dict(
    LAND="#1E1E1E", BUILDING="#2A2A2A", BUILDING_LINE="#333333", PARK="#203126", PARK_DARK="#1C2B21",
    PITCH="#22352A", EDUCATION="#26241F", HOSPITAL="#2C2222", INDUSTRIAL="#232323", PEDESTRIAN="#262626",
    WATER="#182D38", SHORE="#1F3846", ROAD="#3A3A3A", ROAD_CASING="#2D2D2D", HIGHWAY="#4A4A4A",
    HIGHWAY_CASING="#2D2D2D", PATH="#4A4A4A", RAIL="#4E4E4E", BORDER="#5A5470", DISTRICT_LABEL="#9E9E9E",
    STREET_LABEL="#B0B0B0", WATER_LABEL="#6E9BD6", HALO="#1E1E1E", WATER_HALO="#182D38", POI_DEFAULT="#8A96A8",
)
globals().update(LIGHT)

NAME = ["coalesce", ["get", "name:de"], ["get", "name"]]


def zoom(*stops, base=1.5):
    """Width/size by zoom: zoom(12, 1, 16, 8) → exponential interpolation."""
    return ["interpolate", ["exponential", base], ["zoom"], *stops]


def zoom_value(expr, z):
    """The value of a zoom(...) expression at zoom z (MapLibre's exponential interpolation)."""
    base = expr[1][1]
    stops = list(zip(expr[3::2], expr[4::2]))
    if z <= stops[0][0]:
        return stops[0][1]
    for (z0, v0), (z1, v1) in zip(stops, stops[1:]):
        if z <= z1:
            t = (z - z0) / (z1 - z0) if base == 1 else (base ** (z - z0) - 1) / (base ** (z1 - z0) - 1)
            return v0 + (v1 - v0) * t
    return stops[-1][1]


def zoom_sum(a, b):
    """a + b as one zoom curve: MapLibre allows only one zoom interpolation per expression."""
    zooms = sorted(set(a[3::2]) | set(b[3::2]))
    stops = [x for z in zooms for x in (z, round(zoom_value(a, z) + zoom_value(b, z), 2))]
    return ["interpolate", a[1], ["zoom"], *stops]


def kinds(*k):
    return ["in", ["get", "kind"], ["literal", list(k)]]


def details(*k):
    return ["in", ["get", "kind_detail"], ["literal", list(k)]]


NOT_TUNNEL = ["!", ["to-boolean", ["get", "is_tunnel"]]]


LAYER_CODE = r"""
def road(f, width, casing_extra, color=ROAD, casing=ROAD_CASING, minzoom=0, suffix=""):
    f = ["all", f, NOT_TUNNEL]
    return (
        {"id": f"road-{suffix}-casing", "type": "line", "source": "osm", "source-layer": "roads",
         "minzoom": minzoom, "filter": f, "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": casing, "line-width": zoom_sum(width, casing_extra)}},
        {"id": f"road-{suffix}", "type": "line", "source": "osm", "source-layer": "roads",
         "minzoom": minzoom, "filter": f, "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": color, "line-width": width}},
    )


def district(layer_id, kinds_, minzoom, size):
    return {
        "id": layer_id, "type": "symbol", "source": "osm", "source-layer": "places", "minzoom": minzoom,
        "filter": ["in", ["get", "kind"], ["literal", kinds_]],
        "layout": {"text-field": NAME, "text-font": ["Noto Sans Medium"], "text-transform": "uppercase",
                   "text-letter-spacing": 0.12, "text-size": size, "text-max-width": 10, "text-padding": 24},
        "paint": {"text-color": DISTRICT_LABEL, "text-halo-color": HALO, "text-halo-width": 1.5},
    }


PARKS = ["park", "garden", "playground", "recreation_ground", "golf_course", "village_green", "zoo", "grass",
         "meadow", "allotments", "nature_reserve", "national_park"]
FOREST = ["forest", "wood", "cemetery"]

# Places, coloured by kind like Apple Maps (dot + label).
POI_COLORS = [
    (["restaurant", "cafe", "fast_food", "bar", "pub", "ice_cream", "bakery", "biergarten", "food_court"], "#F08A24"),
    (["supermarket", "clothes", "shoes", "convenience", "department_store", "books", "mall", "chemist",
      "optician", "jewelry", "gift", "electronics", "florist", "marketplace"], "#D99A00"),
    (["school", "university", "college", "kindergarten", "library"], "#9A7553"),
    (["hospital", "pharmacy", "doctors", "dentist", "clinic"], "#E5484D"),
    (["museum", "theatre", "cinema", "attraction", "castle", "viewpoint", "arts_centre", "gallery", "monument"], "#9B6AD6"),
    (["park", "garden", "zoo", "sports_centre", "swimming_pool", "stadium", "beach", "marina"], "#3E9A4E"),
    (["train_station", "ferry_terminal", "station"], "#2F7BE5"),
    (["bank", "post_office", "police", "townhall", "place_of_worship", "hotel", "fire_station"], "#6B7A90"),
]
POI_KINDS = [k for ks, _ in POI_COLORS for k in ks]
POI_COLOR = ["match", ["get", "kind"]] + [x for ks, c in POI_COLORS for x in (ks, c)] + [POI_DEFAULT]

minor_w = zoom(13, 0.5, 15, 3, 17, 9, 18, 15)
major_w = zoom(11, 0.8, 13, 2.2, 15, 6, 17, 14, 18, 22)
pedestrian_w = zoom(15, 1.5, 17, 7, 18, 12)
path_w = zoom(15, 0.8, 18, 2.5)

layers = [
    {"id": "water-background", "type": "background", "paint": {"background-color": WATER}},
    {"id": "earth", "type": "fill", "source": "osm", "source-layer": "earth", "paint": {"fill-color": LAND}},
    {"id": "landcover", "type": "fill", "source": "osm", "source-layer": "landcover",
     "filter": kinds("forest", "grassland"), "paint": {"fill-color": PARK, "fill-opacity": 0.7}},
    {"id": "landuse-industrial", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": kinds("industrial", "railway", "commercial"), "paint": {"fill-color": INDUSTRIAL}},
    {"id": "landuse-education", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": kinds("school", "university", "college", "kindergarten"), "paint": {"fill-color": EDUCATION}},
    {"id": "landuse-hospital", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": kinds("hospital"), "paint": {"fill-color": HOSPITAL}},
    {"id": "parks", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": ["in", ["get", "kind"], ["literal", PARKS]], "paint": {"fill-color": PARK}},
    {"id": "forest", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": ["in", ["get", "kind"], ["literal", FOREST]], "paint": {"fill-color": PARK_DARK}},
    {"id": "pitches", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": kinds("pitch", "playground"), "paint": {"fill-color": PITCH}},
    {"id": "pedestrian-areas", "type": "fill", "source": "osm", "source-layer": "landuse",
     "filter": kinds("pedestrian", "platform"), "paint": {"fill-color": PEDESTRIAN}},
    {"id": "water", "type": "fill", "source": "osm", "source-layer": "water",
     "filter": ["==", ["geometry-type"], "Polygon"], "paint": {"fill-color": WATER}},
    {"id": "shore", "type": "line", "source": "osm", "source-layer": "water",
     "filter": ["==", ["geometry-type"], "Polygon"], "minzoom": 12,
     "paint": {"line-color": SHORE, "line-width": zoom(12, 0.5, 16, 1.2)}},
    {"id": "waterways", "type": "line", "source": "osm", "source-layer": "water",
     "filter": ["==", ["geometry-type"], "LineString"],
     "paint": {"line-color": WATER, "line-width": zoom(12, 1, 16, 4)}},
    {"id": "buildings", "type": "fill", "source": "osm", "source-layer": "buildings", "minzoom": 14,
     "filter": kinds("building", "building_part"),
     "paint": {"fill-color": BUILDING, "fill-opacity": zoom(14, 0.3, 15, 1, base=1)}},
    {"id": "buildings-outline", "type": "line", "source": "osm", "source-layer": "buildings", "minzoom": 15,
     "filter": kinds("building", "building_part"),
     "paint": {"line-color": BUILDING_LINE, "line-width": zoom(15, 0.4, 18, 1.2)}},
    # Footpaths, tracks, sidewalks: fine dashes; stairs: tight dashes.
    {"id": "paths", "type": "line", "source": "osm", "source-layer": "roads", "minzoom": 15,
     "filter": ["all", kinds("path"), ["!", details("pedestrian", "steps")], NOT_TUNNEL],
     "layout": {"line-cap": "round"},
     "paint": {"line-color": PATH, "line-width": path_w, "line-dasharray": [2, 1.6]}},
    {"id": "steps", "type": "line", "source": "osm", "source-layer": "roads", "minzoom": 15,
     "filter": ["all", kinds("path"), details("steps")],
     "paint": {"line-color": PATH, "line-width": zoom(15, 2, 18, 5), "line-dasharray": [0.4, 0.4]}},
]
# Pedestrian streets and living streets look like streets (you can walk them).
layers += road(["any", ["all", kinds("path"), details("pedestrian")], ["all", kinds("other"), details("living_street")]],
               pedestrian_w, zoom(15, 0.5, 17, 1.5), minzoom=14, suffix="pedestrian")
layers += road(kinds("minor_road"), minor_w, zoom(13, 0.5, 16, 1.5), minzoom=12, suffix="minor")
layers += road(kinds("major_road"), major_w, zoom(11, 0.5, 16, 2), suffix="major")
layers += road(kinds("highway"), major_w, zoom(11, 0.8, 16, 2.5), color=HIGHWAY, casing=HIGHWAY_CASING, suffix="highway")
layers += [
    {"id": "rail", "type": "line", "source": "osm", "source-layer": "roads",
     "filter": ["==", ["get", "kind"], "rail"],
     "paint": {"line-color": RAIL, "line-width": zoom(12, 1, 16, 2), "line-dasharray": [3, 2]}},
    {"id": "border", "type": "line", "source": "osm", "source-layer": "boundaries",
     "filter": ["==", ["get", "kind"], "country"],
     "paint": {"line-color": BORDER, "line-width": 1.5, "line-dasharray": [4, 3]}},
    {"id": "street-names", "type": "symbol", "source": "osm", "source-layer": "roads", "minzoom": 14.3,
     "filter": ["all", ["has", "name"], ["any", kinds("minor_road", "major_road", "highway", "other"),
                                         ["all", kinds("path"), details("pedestrian", "footway", "path", "cycleway")]]],
     "layout": {"symbol-placement": "line", "text-field": NAME, "text-font": ["Noto Sans Medium"],
                "text-size": zoom(14, 10, 17, 13, base=1), "text-max-angle": 30, "symbol-spacing": 220},
     "paint": {"text-color": STREET_LABEL, "text-halo-color": HALO, "text-halo-width": 1.6}},
    {"id": "water-names", "type": "symbol", "source": "osm", "source-layer": "water",
     "filter": ["all", ["==", ["geometry-type"], "Point"], ["has", "name"]],
     "layout": {"text-field": NAME, "text-font": ["Noto Sans Italic"], "text-size": 13, "text-max-width": 8,
                "text-letter-spacing": 0.05},
     "paint": {"text-color": WATER_LABEL, "text-halo-color": WATER_HALO, "text-halo-width": 1.2}},
    # No shops, cafés or other places: the map shows streets, water, parks and the bus stops (drawn by the
    # app), nothing else (decided after testing on a phone: the places made the map busy).
    # Towns and districts (KONSTANZ, PETERSHAUSEN …) — uppercase and spaced like the design's DistrictLabel;
    # the many small neighbourhoods only when zoomed in.
    district("district-names", ["locality", "macrohood"], minzoom=0, size=12),
]

"""


def build(palette, name):
    """The style in one palette. The layer code reads the colour names as globals."""
    globals().update(palette)
    exec(LAYER_CODE, globals())
    style = {
        "version": 8,
        "name": name,
        "glyphs": "asset://map/fonts/{fontstack}/{range}.pbf",
        "sources": {
            "osm": {
                "type": "vector",
                "url": "pmtiles://asset://map/konstanz.pmtiles",
                "attribution": "© OpenStreetMap",
            }
        },
        "layers": layers,
    }
    return style


for palette, file, title in [(LIGHT, "style.json", "KonstanzGo"), (DARK, "style-dark.json", "KonstanzGo dark")]:
    style = build(palette, title)
    (OUT / file).write_text(json.dumps(style, ensure_ascii=False, indent=1))
    print(f"{OUT / file}: {len(style['layers'])} layers")
