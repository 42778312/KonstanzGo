#!/usr/bin/env python3
"""
Writes App/Resources/Data/map/style.json: the MapLibre style for the offline Konstanz map,
in a light palette close to Apple Maps.

    python3 DataPipeline/map/make_style.py

Tiles: Protomaps basemap (OpenStreetMap), schema v4, cut to Konstanz with
    pmtiles extract https://build.protomaps.com/<yyyymmdd>.pmtiles konstanz.pmtiles --bbox=9.05,47.63,9.26,47.74 --maxzoom=15
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "App/Resources/Data/map/style.json"

# Palette close to Apple Maps (light): warm land, soft blue water, fresh greens, white streets,
# yellow motorways, buildings with a fine outline, colour-coded places.
LAND = "#F6F4EF"
BUILDING = "#EDEAE5"
BUILDING_LINE = "#DEDAD3"
PARK = "#CFE8C0"
PARK_DARK = "#BFDDAB"
PITCH = "#C2E3B2"
EDUCATION = "#F1E8D8"
HOSPITAL = "#F7E0DE"
INDUSTRIAL = "#ECE9E4"
PEDESTRIAN = "#FBFAF7"
WATER = "#A7D3F2"
SHORE = "#93C4E8"
ROAD = "#FFFFFF"
ROAD_CASING = "#D9D3C9"
HIGHWAY = "#FFD873"
HIGHWAY_CASING = "#E5B64C"
PATH = "#C9C2B6"
RAIL = "#B8B2A8"
BORDER = "#B9B2C6"
DISTRICT_LABEL = "#7D828B"
STREET_LABEL = "#5E6168"
WATER_LABEL = "#3F7FB5"
HALO = "#FFFFFF"

NAME = ["coalesce", ["get", "name:de"], ["get", "name"]]


def zoom(*stops, base=1.5):
    """Width/size by zoom: zoom(12, 1, 16, 8) → exponential interpolation."""
    return ["interpolate", ["exponential", base], ["zoom"], *stops]


def kinds(*k):
    return ["in", ["get", "kind"], ["literal", list(k)]]


def details(*k):
    return ["in", ["get", "kind_detail"], ["literal", list(k)]]


NOT_TUNNEL = ["!", ["to-boolean", ["get", "is_tunnel"]]]


def road(f, width, casing_extra, color=ROAD, casing=ROAD_CASING, minzoom=0, suffix=""):
    f = ["all", f, NOT_TUNNEL]
    return (
        {"id": f"road-{suffix}-casing", "type": "line", "source": "osm", "source-layer": "roads",
         "minzoom": minzoom, "filter": f, "layout": {"line-cap": "round", "line-join": "round"},
         "paint": {"line-color": casing, "line-width": ["+", width, casing_extra]}},
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
POI_COLOR = ["match", ["get", "kind"]] + [x for ks, c in POI_COLORS for x in (ks, c)] + ["#6B7A90"]

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
     "paint": {"text-color": WATER_LABEL, "text-halo-color": "#D6EBF8", "text-halo-width": 1.2}},
    # Places: a coloured dot with a white ring and the name under it.
    {"id": "poi-dots", "type": "circle", "source": "osm", "source-layer": "pois", "minzoom": 16,
     "filter": ["all", ["in", ["get", "kind"], ["literal", POI_KINDS]], ["has", "name"]],
     "paint": {"circle-color": POI_COLOR, "circle-radius": zoom(16, 3.5, 18, 5.5, base=1),
               "circle-stroke-color": HALO, "circle-stroke-width": 1.5}},
    {"id": "poi-names", "type": "symbol", "source": "osm", "source-layer": "pois", "minzoom": 16,
     "filter": ["all", ["in", ["get", "kind"], ["literal", POI_KINDS]], ["has", "name"]],
     "layout": {"text-field": NAME, "text-font": ["Noto Sans Medium"], "text-size": 11, "text-max-width": 8,
                "text-anchor": "top", "text-offset": [0, 0.7], "text-padding": 4, "text-optional": True},
     "paint": {"text-color": POI_COLOR, "text-halo-color": HALO, "text-halo-width": 1.5}},
    # Towns and districts (KONSTANZ, PETERSHAUSEN …) — uppercase and spaced like the design's DistrictLabel;
    # the many small neighbourhoods only when zoomed in.
    district("district-names", ["locality", "macrohood"], minzoom=0, size=12),
    district("neighbourhood-names", ["neighbourhood"], minzoom=14, size=11),
]

style = {
    "version": 8,
    "name": "Konstanz Transit",
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
OUT.write_text(json.dumps(style, ensure_ascii=False, indent=1))
print(f"{OUT}: {len(layers)} layers")
