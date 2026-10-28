#!/usr/bin/env python3
"""
Fills the place tables of App/Resources/Data/timetable.db from the offline map tiles
(App/Resources/Data/map/konstanz.pmtiles, OpenStreetMap via Protomaps): named places, streets,
districts and towns — so search, planning and "what's here?" use the same data the map shows.

Run after DataPipeline/gtfs-import/import_gtfs.py (which creates the tables):

    python3 -m venv DataPipeline/places-import/.venv
    DataPipeline/places-import/.venv/bin/pip install pmtiles mapbox-vector-tile
    DataPipeline/places-import/.venv/bin/python DataPipeline/places-import/import_places.py

Data © OpenStreetMap contributors, ODbL.
"""
import gzip
import math
import re
import sqlite3
import unicodedata
from collections import defaultdict
from pathlib import Path

import mapbox_vector_tile
from pmtiles.reader import MmapSource, Reader, all_tiles

ROOT = Path(__file__).resolve().parents[2]
TILES = ROOT / "App/Resources/Data/map/konstanz.pmtiles"
DB = ROOT / "App/Resources/Data/timetable.db"
ZOOM = 15  # the most detailed level in the archive

# OSM kind → (app kind, what it is, importance). Everything else (benches, memorials, parking …) is left out.
POI_KINDS = {
    "university": ("University", "University", 100), "college": ("University", "College", 70),
    "station": ("Station", "Train station", 90), "ferry_terminal": ("Harbour", "Pier", 80),
    "marina": ("Harbour", "Marina", 45), "hospital": ("Venue", "Hospital", 75),
    "museum": ("Venue", "Museum", 65), "theatre": ("Venue", "Theatre", 65), "cinema": ("Venue", "Cinema", 55),
    "stadium": ("Venue", "Stadium", 60), "sports_centre": ("Venue", "Sports centre", 45),
    "zoo": ("Venue", "Zoo", 60), "park": ("Venue", "Park", 50), "garden": ("Venue", "Garden", 45),
    "beach": ("Venue", "Beach", 50), "library": ("Library", "Library", 55), "townhall": ("Venue", "Town hall", 55),
    "attraction": ("Venue", "Sight", 60), "castle": ("Venue", "Castle", 55), "viewpoint": ("Venue", "Viewpoint", 40),
    "marketplace": ("Square", "Market", 50), "water_park": ("Venue", "Pool", 60),
    "mall": ("Venue", "Shopping centre", 65), "department_store": ("Venue", "Department store", 55),
    "supermarket": ("Venue", "Supermarket", 35), "place_of_worship": ("Venue", "Church", 40),
    "hotel": ("Venue", "Hotel", 35), "school": ("Venue", "School", 40), "restaurant": ("Venue", "Restaurant", 25),
    "cafe": ("Venue", "Café", 25), "bar": ("Venue", "Bar", 20), "pub": ("Venue", "Pub", 20),
    "fast_food": ("Venue", "Fast food", 15), "bakery": ("Venue", "Bakery", 15),
    "pharmacy": ("Venue", "Pharmacy", 30), "post_office": ("Venue", "Post office", 35),
    "police": ("Venue", "Police", 40), "swimming_area": ("Venue", "Swimming area", 45),
}
STREET_KINDS = {"major_road", "minor_road", "highway"}
DISTRICT_KINDS = {"neighbourhood", "macrohood"}
TOWN_DETAILS = {"city", "town", "village"}
# Towns on the Swiss side of the border (the rest of the area is German).
SWISS = {"Kreuzlingen", "Bottighofen", "Ermatingen", "Fruthwilen", "Gottlieben", "Mannenbach-Salenstein",
         "Münsterlingen", "Raperswilen", "Salenstein", "Scherzingen", "Triboltingen", "Tägerwilen", "Wäldi",
         "Bernrainzelg"}


def fold(text):
    """Same as the app: lowercase, ß → ss, accents removed."""
    text = text.lower().replace("ß", "ss")
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def slug(name):
    """Same as the app's stop ids: "Universität Konstanz" → "universitaet-konstanz"."""
    s = name.lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def meters(a, b):
    kx = 111_320 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[1] - b[1]) * kx, (a[0] - b[0]) * 111_180)


def tile_to_latlon(x, y, gx, gy, extent):
    n = 2 ** ZOOM
    px, py = (x + gx / extent) / n, (y + gy / extent) / n
    return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * py)))), px * 360 - 180


def lines_of(geometry):
    t, c = geometry["type"], geometry["coordinates"]
    return [c] if t == "LineString" else c if t == "MultiLineString" else []


def read_tiles():
    pois, streets, districts, towns = [], defaultdict(list), [], []
    reader = Reader(MmapSource(open(TILES, "rb")))
    for (z, x, y), data in all_tiles(reader.get_bytes):
        if z != ZOOM:
            continue
        tile = mapbox_vector_tile.decode(gzip.decompress(data), default_options={"y_coord_down": True})

        def at(gx, gy, layer):
            return tile_to_latlon(x, y, gx, gy, tile[layer]["extent"])

        for f in tile.get("pois", {}).get("features", []):
            p, g = f["properties"], f["geometry"]
            if p.get("name") and p.get("kind") in POI_KINDS and g["type"] == "Point":
                pois.append((p["name"], p["kind"], at(*g["coordinates"], "pois")))
        for f in tile.get("roads", {}).get("features", []):
            p = f["properties"]
            if p.get("name") and p.get("kind") in STREET_KINDS:
                for line in lines_of(f["geometry"]):
                    streets[p["name"]] += [at(gx, gy, "roads") for gx, gy in line]
        for f in tile.get("places", {}).get("features", []):
            p, g = f["properties"], f["geometry"]
            if not p.get("name") or g["type"] != "Point":
                continue
            point = at(*g["coordinates"], "places")
            if p.get("kind") in DISTRICT_KINDS or p.get("kind_detail") == "suburb":
                districts.append((p["name"], point))
            elif p.get("kind") == "locality" and p.get("kind_detail") in TOWN_DETAILS:
                towns.append((p["name"], point, p["kind_detail"] != "village"))
    unique_towns = []
    for name, point, big in towns:
        if not any(n == name and meters(p, point) < 300 for n, p, _ in unique_towns):
            unique_towns.append((name, point, big))
    return pois, streets, dedupe(districts), unique_towns


def dedupe(named_points, radius=300):
    out = []
    for name, point in named_points:
        if not any(n == name and meters(p, point) < radius for n, p in out):
            out.append((name, point))
    return out


def cluster(points, gap=250):
    """Split one street name into separate streets (the same name in two villages)."""
    parent = list(range(len(points)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    cell = defaultdict(list)
    size = gap / 111_000
    for i, (lat, lon) in enumerate(points):
        cx, cy = int(lon / size), int(lat / size)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in cell.get((cx + dx, cy + dy), []):
                    if meters(points[i], points[j]) <= gap:
                        parent[root(i)] = root(j)
        cell[(cx, cy)].append(i)
    groups = defaultdict(list)
    for i, p in enumerate(points):
        groups[root(i)].append(p)
    return list(groups.values())


def thin(points, step=35):
    out = []
    for p in points:
        if all(meters(p, q) >= step for q in out[-8:]):
            out.append(p)
    return out


def main():
    pois, streets, districts, towns = read_tiles()

    def nearest(options, point, max_m):
        best = min(options, key=lambda o: meters(o[1], point), default=None)
        return best[0] if best and meters(best[1], point) <= max_m else None

    big_towns = [(n, p) for n, p, big in towns if big]
    all_towns = [(n, p) for n, p, _ in towns]

    def town_of(point):
        """Konstanz or Kreuzlingen when within 5 km, otherwise the nearest village."""
        return nearest(big_towns, point, 5000) or nearest(all_towns, point, 4000)

    def area(point):
        town = town_of(point)
        district = nearest(districts, point, 1200)
        parts = [p for p in (district, town) if p]
        if len(parts) == 2 and parts[0] == parts[1]:
            parts = parts[:1]
        return ", ".join(parts)

    rows, street_points, used = [], [], set()

    def add(name, kind, detail, where, point, rank):
        base = slug(name)
        s = base
        n = 2
        while s in used:
            s, n = f"{base}-{n}", n + 1
        used.add(s)
        rows.append((len(rows) + 1, s, name, kind, detail, where, point[0], point[1], fold(name), rank))
        return len(rows)

    # Named places, one per name and kind within 300 m (a big building can be tagged twice).
    seen = []
    for name, kind, point in pois:
        if any(n == name and k == kind and meters(p, point) < 300 for n, k, p in seen):
            continue
        seen.append((name, kind, point))
        app_kind, detail, rank = POI_KINDS[kind]
        add(name, app_kind, detail, area(point), point, rank)

    # Streets: representative point = the vertex closest to the street's middle.
    for name, points in streets.items():
        for group in cluster(points):
            lat = sum(p[0] for p in group) / len(group)
            lon = sum(p[1] for p in group) / len(group)
            middle = min(group, key=lambda p: meters(p, (lat, lon)))
            pid = add(name, "Street", "Street", area(middle), middle, 30)
            street_points += [(pid, p[0], p[1]) for p in thin(group)]

    for name, point in districts:
        add(name, "District", town_of(point) or "", "", point, 0)
    # Rank 1 = town (Konstanz, Kreuzlingen), 0 = village: "what's here?" prefers towns nearby.
    for name, point, big in towns:
        add(name, "Town", "Switzerland" if name in SWISS else "Germany", "", point, 1 if big else 0)

    db = sqlite3.connect(DB)
    db.execute("DELETE FROM street_point")
    db.execute("DELETE FROM place")
    db.executemany("INSERT INTO place (id, slug, name, kind, detail, area, lat, lon, search_name, rank) "
                   "VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    db.executemany("INSERT INTO street_point (place_id, lat, lon) VALUES (?,?,?)", street_points)
    db.execute("INSERT OR REPLACE INTO meta VALUES ('places_source', 'OpenStreetMap via Protomaps basemap tiles')")
    # Date of the OpenStreetMap data in the map, "2026-09-29T04:00:00Z" → 20260929 (shown in Offline data).
    osm_time = Reader(MmapSource(open(TILES, "rb"))).metadata().get("planetiler:osm:osmosisreplicationtime", "")
    if osm_time:
        db.execute("INSERT OR REPLACE INTO meta VALUES ('map_date', ?)", (osm_time[:10].replace("-", ""),))
    db.commit()
    db.execute("VACUUM")
    db.close()

    kinds = defaultdict(int)
    for r in rows:
        kinds[r[3]] += 1
    print(f"{len(rows)} places {dict(kinds)}, {len(street_points)} street points")
    print(f"{DB.relative_to(ROOT)}: {DB.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
