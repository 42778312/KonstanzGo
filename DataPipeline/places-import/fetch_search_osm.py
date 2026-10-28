#!/usr/bin/env python3
"""
Downloads what people search for around Konstanz from OpenStreetMap (Overpass), in small tiles:
every named shop, café, school, doctor, office, sight … and every house address.
Writes data/search-osm.json for build_search.py.

    python3 DataPipeline/places-import/fetch_search_osm.py

Data © OpenStreetMap contributors, ODbL.
"""
import json
import os
import time
import urllib.parse
import urllib.request

SOUTH, WEST, NORTH, EAST = 47.63, 9.05, 47.74, 9.26
STEP = 0.04
SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/DataPipeline/overpass/api/interpreter",
]
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")

KEYS = ["amenity", "shop", "tourism", "leisure", "office", "craft", "healthcare", "historic", "sport", "club"]


def query(s, w, n, e):
    b = f"({s},{w},{n},{e})"
    parts = [f'nwr["name"]["{k}"]{b};' for k in KEYS]
    parts += [
        f'nwr["name"]["building"~"^(school|university|college|kindergarten|church|chapel|hospital|train_station|civic|public|stadium|museum|hotel|government|dormitory)$"]{b};',
        f'nwr["name"]["place"~"^(square|locality|neighbourhood|quarter|suburb|island|islet|hamlet|village)$"]{b};',
        f'nwr["name"]["natural"~"^(beach|peak|wood|bay|cape|spring)$"]{b};',
        f'nwr["name"]["landuse"~"^(recreation_ground|cemetery|allotments|forest)$"]{b};',
        f'nwr["name"]["public_transport"="station"]{b};',
        f'nwr["name"]["railway"~"^(station|halt)$"]{b};',
        f'nwr["name"]["man_made"~"^(lighthouse|tower|pier)$"]{b};',
        f'nwr["name"]["bridge"="yes"]["highway"]{b};',
        f'nwr["addr:housenumber"]["addr:street"]{b};',
    ]
    return "[out:json][timeout:120];(" + "".join(parts) + ");out center tags qt;"


def fetch(s, w, n, e):
    body = urllib.parse.urlencode({"data": query(s, w, n, e)}).encode()
    for attempt in range(10):
        url = SERVERS[attempt % len(SERVERS)]
        try:
            req = urllib.request.Request(url, body, {"User-Agent": "konstanz-transit-dev/1.0"})
            with urllib.request.urlopen(req, timeout=150) as r:
                return json.load(r)["elements"]
        except Exception as ex:  # busy server: wait and try the other one
            print(f"  retry {attempt + 1} ({ex})", flush=True)
            time.sleep(5 + attempt * 5)
    raise SystemExit(f"tile {s},{w} failed")


def main():
    found = {}
    lat = SOUTH
    while lat < NORTH - 1e-9:
        lon = WEST
        while lon < EAST - 1e-9:
            cache = os.path.join(DATA, "search-tiles", f"{lat:.3f}_{lon:.3f}.json")
            if os.path.exists(cache):
                with open(cache) as f:
                    els = json.load(f)
            else:
                els = fetch(lat, lon, min(lat + STEP, NORTH), min(lon + STEP, EAST))
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                with open(cache, "w") as f:
                    json.dump(els, f)
                time.sleep(1)
            for el in els:
                c = el.get("center") or ({"lat": el["lat"], "lon": el["lon"]} if "lat" in el else None)
                if c:
                    found[f'{el["type"]}{el["id"]}'] = {"tags": el.get("tags", {}), "lat": c["lat"], "lon": c["lon"]}
            print(f"{lat:.3f},{lon:.3f}: {len(els)} elements, total {len(found)}", flush=True)
            lon += STEP
        lat += STEP
    with open(os.path.join(DATA, "search-osm.json"), "w") as f:
        json.dump(found, f)


if __name__ == "__main__":
    main()
